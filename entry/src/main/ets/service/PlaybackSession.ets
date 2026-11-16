import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, Callback, ErrorCallback } from '@kit.BasicServicesKit';
import { CleanupLog, LogKind } from '../model/CleanupLog';
import { ResourceTracker, TrackedResource } from '../model/ResourceTracker';
import { CleanupError, Releasable } from '../model/CleanupError';
import {
  ERR_ERROR_STATE,
  ERR_SESSION_RELEASED,
  ERR_STATE_TIMEOUT,
  FD_URL_PREFIX,
  PATH_SEPARATOR,
  PlayerState,
  STATE_WAIT_TIMEOUT_MS
} from '../common/Constants';
import { delay } from '../common/TimeUtils';

export enum SourceKind {
  RAWFILE = 0,
  SANDBOX_FILE = 1
}

export class PlaybackSource {
  kind: SourceKind;
  name: string;

  constructor(kind: SourceKind, name: string) {
    this.kind = kind;
    this.name = name;
  }
}

class StateWaiter {
  target: string;
  resolve: () => void;
  reject: (code: number) => void;
  timerId: number = -1;

  constructor(target: string, resolve: () => void, reject: (code: number) => void) {
    this.target = target;
    this.resolve = resolve;
    this.reject = reject;
  }
}

/**
 * Owns one AVPlayer and the file descriptor it reads from.
 *
 * Resource rules followed here:
 * 1. Every resource is recorded the moment it is acquired, so release() knows exactly what to free.
 * 2. release() is idempotent: concurrent or repeated calls share one cleanup run.
 * 3. Each cleanup step has its own try/catch, so one failure never skips the next step.
 * 4. The fd is closed only after the player that reads it has been released.
 */
export class PlaybackSession implements Releasable {
  private context: common.UIAbilityContext;
  private source: PlaybackSource;
  private log: CleanupLog;
  private tracker: ResourceTracker;
  private player: media.AVPlayer | undefined = undefined;
  private rawFdOpened: boolean = false;
  private sandboxFd: number = -1;
  private releasePromise: Promise<void> | undefined = undefined;
  private waiters: StateWaiter[] = [];

  constructor(context: common.UIAbilityContext, source: PlaybackSource, log: CleanupLog,
    tracker: ResourceTracker) {
    this.context = context;
    this.source = source;
    this.log = log;
    this.tracker = tracker;
  }

  /** Creates the player, opens the source fd and prepares. Throws on any failure; the caller cleans up. */
  async open(): Promise<void> {
    const player = await media.createAVPlayer();
    if (this.isReleasing()) {
      await player.release();
      throw new CleanupError(ERR_SESSION_RELEASED, 'released during open');
    }
    this.player = player;
    this.tracker.acquire(TrackedResource.PLAYER);
    this.log.add(LogKind.STEP, 'log_player_created');
    this.registerListeners(player);

    if (this.source.kind === SourceKind.RAWFILE) {
      await this.openRawFile();
    } else {
      await this.openSandboxFile();
    }

    await this.waitForState(PlayerState.INITIALIZED);
    await this.requirePlayer().prepare();
    this.log.add(LogKind.STEP, 'log_player_prepared', this.requirePlayer().duration);
  }

  async play(durationMs: number): Promise<void> {
    await this.requirePlayer().play();
    this.log.add(LogKind.STEP, 'log_player_playing', durationMs);
    await delay(durationMs);
  }

  async stop(): Promise<void> {
    const player = this.player;
    if (player === undefined) {
      return;
    }
    const state: string = player.state;
    if (state === PlayerState.PREPARED || state === PlayerState.PLAYING ||
      state === PlayerState.PAUSED || state === PlayerState.COMPLETED) {
      await player.stop();
      this.log.add(LogKind.STEP, 'log_player_stopped');
    }
  }

  /** Safe to call any number of times, from any path. Never rejects. */
  release(): Promise<void> {
    if (this.releasePromise !== undefined) {
      this.log.add(LogKind.CLEANUP, 'log_release_reused');
      return this.releasePromise;
    }
    this.releasePromise = this.doRelease();
    return this.releasePromise;
  }

  private async doRelease(): Promise<void> {
    this.rejectWaiters();

    // Step 1: listeners and player
    const player = this.player;
    this.player = undefined;
    if (player !== undefined) {
      this.unregisterListeners(player);
      this.log.add(LogKind.CLEANUP, 'log_listeners_removed');
      try {
        const state: string = player.state;
        if (state !== PlayerState.RELEASED) {
          await player.release();
        }
        this.log.add(LogKind.CLEANUP, 'log_player_released');
      } catch (error) {
        const err = error as BusinessError;
        this.log.add(LogKind.ERROR, 'log_release_failed', err.code, err.message ?? '');
      } finally {
        this.tracker.release(TrackedResource.PLAYER);
      }
    } else {
      this.log.add(LogKind.CLEANUP, 'log_no_player');
    }

    // Step 2: the fd, only after the player that reads it is gone.
    await this.closeSourceFd();
  }

  private async openRawFile(): Promise<void> {
    // Throws 9001005 if the rawfile does not exist. In that case no fd was opened.
    const rawFd = await this.context.resourceManager.getRawFd(this.source.name);
    if (this.isReleasing()) {
      await this.context.resourceManager.closeRawFd(this.source.name);
      throw new CleanupError(ERR_SESSION_RELEASED, 'released during open');
    }
    this.rawFdOpened = true;
    this.tracker.acquire(TrackedResource.RAW_FD);
    this.log.add(LogKind.STEP, 'log_rawfd_opened', this.source.name);
    this.requirePlayer().fdSrc = rawFd;
  }

  private async openSandboxFile(): Promise<void> {
    const path = this.context.filesDir + PATH_SEPARATOR + this.source.name;
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    if (this.isReleasing()) {
      await fileIo.close(file);
      throw new CleanupError(ERR_SESSION_RELEASED, 'released during open');
    }
    this.sandboxFd = file.fd;
    this.tracker.acquire(TrackedResource.FILE_FD);
    this.log.add(LogKind.STEP, 'log_sandbox_fd_opened', file.fd);
    this.requirePlayer().url = FD_URL_PREFIX + file.fd.toString();
  }

  private async closeSourceFd(): Promise<void> {
    if (this.source.kind === SourceKind.RAWFILE) {
      if (!this.rawFdOpened) {
        // getRawFd() failed or was never reached: closing here would be wrong.
        this.log.add(LogKind.CLEANUP, 'log_rawfd_skip');
        return;
      }
      try {
        await this.context.resourceManager.closeRawFd(this.source.name);
        this.log.add(LogKind.CLEANUP, 'log_rawfd_closed');
      } catch (error) {
        const err = error as BusinessError;
        this.log.add(LogKind.ERROR, 'log_release_failed', err.code, err.message ?? '');
      } finally {
        this.rawFdOpened = false;
        this.tracker.release(TrackedResource.RAW_FD);
      }
      return;
    }

    if (this.sandboxFd < 0) {
      this.log.add(LogKind.CLEANUP, 'log_fd_skip');
      return;
    }
    try {
      await fileIo.close(this.sandboxFd);
      this.log.add(LogKind.CLEANUP, 'log_sandbox_fd_closed');
    } catch (error) {
      const err = error as BusinessError;
      this.log.add(LogKind.ERROR, 'log_release_failed', err.code, err.message ?? '');
    } finally {
      this.sandboxFd = -1;
      this.tracker.release(TrackedResource.FILE_FD);
    }
  }

  // ---------- Listeners ----------

  private onStateChange: media.OnAVPlayerStateChangeHandle =
    (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
      const current: string = state;
      this.log.add(LogKind.STEP, 'log_player_state', current);
      this.settleWaiters(current);
      if (current === PlayerState.ERROR) {
        this.log.add(LogKind.CLEANUP, 'log_error_state_release');
        this.release();
      }
    };

  private onError: ErrorCallback = (error: BusinessError): void => {
    this.log.add(LogKind.ERROR, 'log_player_error', error.code, error.message ?? '');
  };

  private onAudioInterrupt: Callback<audio.InterruptEvent> = (event: audio.InterruptEvent): void => {
    if (event.forceType === audio.InterruptForceType.INTERRUPT_FORCE) {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        this.log.add(LogKind.CLEANUP, 'log_interrupt_stop');
        this.release();
      } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        this.log.add(LogKind.STEP, 'log_interrupt_pause');
      }
      return;
    }
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      this.log.add(LogKind.STEP, 'log_interrupt_pause');
      this.pauseSafely();
    } else if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      this.log.add(LogKind.STEP, 'log_interrupt_resume');
      this.resumeSafely();
    }
  };

  private onOutputDeviceChange: Callback<audio.AudioStreamDeviceChangeInfo> =
    (info: audio.AudioStreamDeviceChangeInfo): void => {
      if (info.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
        this.log.add(LogKind.STEP, 'log_device_unavailable');
        this.pauseSafely();
      }
    };

  private registerListeners(player: media.AVPlayer): void {
    player.on('stateChange', this.onStateChange);
    player.on('error', this.onError);
    player.on('audioInterrupt', this.onAudioInterrupt);
    player.on('audioOutputDeviceChangeWithInfo', this.onOutputDeviceChange);
  }

  private unregisterListeners(player: media.AVPlayer): void {
    player.off('stateChange', this.onStateChange);
    player.off('error', this.onError);
    player.off('audioInterrupt', this.onAudioInterrupt);
    player.off('audioOutputDeviceChangeWithInfo', this.onOutputDeviceChange);
  }

  private pauseSafely(): void {
    const player = this.player;
    if (player === undefined) {
      return;
    }
    const state: string = player.state;
    if (state === PlayerState.PLAYING) {
      player.pause().catch((error: BusinessError) => {
        this.log.add(LogKind.ERROR, 'log_player_error', error.code, error.message ?? '');
      });
    }
  }

  private resumeSafely(): void {
    const player = this.player;
    if (player === undefined) {
      return;
    }
    const state: string = player.state;
    if (state === PlayerState.PAUSED) {
      player.play().catch((error: BusinessError) => {
        this.log.add(LogKind.ERROR, 'log_player_error', error.code, error.message ?? '');
      });
    }
  }

  // ---------- State waiting ----------

  private waitForState(target: string): Promise<void> {
    const current: string = this.requirePlayer().state;
    if (current === target) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve, reject) => {
      const waiter = new StateWaiter(target, () => resolve(),
        (code: number) => reject(new CleanupError(code, target)));
      waiter.timerId = setTimeout(() => {
        this.removeWaiter(waiter);
        reject(new CleanupError(ERR_STATE_TIMEOUT, target));
      }, STATE_WAIT_TIMEOUT_MS);
      this.waiters.push(waiter);
    });
  }

  private settleWaiters(state: string): void {
    const pending: StateWaiter[] = [];
    this.waiters.forEach((waiter: StateWaiter) => {
      if (waiter.target === state) {
        clearTimeout(waiter.timerId);
        waiter.resolve();
      } else if (state === PlayerState.ERROR) {
        clearTimeout(waiter.timerId);
        waiter.reject(ERR_ERROR_STATE);
      } else {
        pending.push(waiter);
      }
    });
    this.waiters = pending;
  }

  private rejectWaiters(): void {
    this.waiters.forEach((waiter: StateWaiter) => {
      clearTimeout(waiter.timerId);
      waiter.reject(ERR_SESSION_RELEASED);
    });
    this.waiters = [];
  }

  private removeWaiter(target: StateWaiter): void {
    this.waiters = this.waiters.filter((waiter: StateWaiter) => waiter !== target);
  }

  // ---------- Helpers ----------

  private isReleasing(): boolean {
    return this.releasePromise !== undefined;
  }

  private requirePlayer(): media.AVPlayer {
    if (this.player === undefined) {
      throw new CleanupError(ERR_SESSION_RELEASED, 'player released');
    }
    return this.player;
  }
}
