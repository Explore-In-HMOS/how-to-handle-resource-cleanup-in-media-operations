import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CleanupLog, LogKind } from '../model/CleanupLog';
import { ResourceTracker, TrackedResource } from '../model/ResourceTracker';
import { Releasable } from '../model/CleanupError';
import { ScenarioId, ScenarioItem } from '../model/Scenario';
import { PlaybackSession, PlaybackSource, SourceKind } from './PlaybackSession';
import { RecordingSession } from './RecordingSession';
import { PermissionHelper } from './PermissionHelper';
import {
  ERR_ERROR_STATE,
  ERR_INVALID_PARAMETER,
  ERR_INVALID_RAWFILE_PATH,
  ERR_OPERATION_NOT_ALLOWED,
  ERR_PERMISSION_DENIED,
  ERR_SESSION_RELEASED,
  ERR_STATE_TIMEOUT,
  ERR_UNSUPPORTED_FORMAT,
  INVALID_SAMPLE_RATE,
  PLAYBACK_DEMO_MS,
  RAW_CORRUPT_AUDIO,
  RAW_MISSING_AUDIO,
  RAW_VALID_AUDIO,
  RECORD_DEMO_MS,
  RECORD_FILE_NAME,
  RECORD_SAMPLE_RATE,
  SHORT_PLAYBACK_MS
} from '../common/Constants';

/**
 * Runs each scenario with the same shape:
 *
 *   const session = new Session(...);
 *   try     { open, use, stop }          // any step may throw
 *   catch   { report the error }         // never rethrow before cleanup
 *   finally { await session.release() }  // runs on success, failure and early return
 */
export class ScenarioRunner {
  private context: common.UIAbilityContext;
  private log: CleanupLog;
  private tracker: ResourceTracker;
  private active: Set<Releasable> = new Set<Releasable>();

  constructor(context: common.UIAbilityContext, log: CleanupLog, tracker: ResourceTracker) {
    this.context = context;
    this.log = log;
    this.tracker = tracker;
  }

  /** Runs one scenario and returns the number of resources still open afterwards (0 = no leak). */
  async run(item: ScenarioItem): Promise<number> {
    try {
      switch (item.id) {
        case ScenarioId.CLEAN_PLAYBACK:
          await this.runPlayback(new PlaybackSource(SourceKind.RAWFILE, RAW_VALID_AUDIO), PLAYBACK_DEMO_MS);
          break;
        case ScenarioId.MISSING_FILE:
          await this.runPlayback(new PlaybackSource(SourceKind.RAWFILE, RAW_MISSING_AUDIO), PLAYBACK_DEMO_MS);
          break;
        case ScenarioId.CORRUPT_FILE:
          await this.runPlayback(new PlaybackSource(SourceKind.RAWFILE, RAW_CORRUPT_AUDIO), PLAYBACK_DEMO_MS);
          break;
        case ScenarioId.DOUBLE_RELEASE:
          await this.runDoubleRelease();
          break;
        case ScenarioId.RECORD_AND_PLAY:
          await this.runRecordAndPlay();
          break;
        case ScenarioId.FAILED_RECORDING:
          await this.runFailedRecording();
          break;
        default:
          break;
      }
    } finally {
      const open = this.tracker.current().total();
      if (open === 0) {
        this.log.add(LogKind.RESULT, 'log_all_released');
      } else {
        this.log.add(LogKind.ERROR, 'log_leak_detected', open);
      }
    }
    return this.tracker.current().total();
  }

  /** Called when the page goes away mid-scenario. */
  async releaseAll(): Promise<void> {
    if (this.active.size === 0) {
      return;
    }
    this.log.add(LogKind.CLEANUP, 'log_exit_cleanup');
    const pending: Promise<void>[] = [];
    this.active.forEach((session: Releasable) => {
      pending.push(session.release());
    });
    await Promise.all(pending);
    this.active.clear();
  }

  // ---------- Scenarios 1-3: playback ----------

  private async runPlayback(source: PlaybackSource, durationMs: number): Promise<boolean> {
    const session = new PlaybackSession(this.context, source, this.log, this.tracker);
    this.active.add(session);
    let succeeded = false;
    try {
      await session.open();
      await session.play(durationMs);
      await session.stop();
      succeeded = true;
    } catch (error) {
      this.reportError(error as BusinessError);
    } finally {
      await session.release();
      this.active.delete(session);
    }
    return succeeded;
  }

  // ---------- Scenario 4: release called from two paths ----------

  private async runDoubleRelease(): Promise<void> {
    // Part A: unguarded. A second release() on the same AVPlayer is an invalid state transition.
    this.log.add(LogKind.STEP, 'log_naive_title');
    let naiveHeld = false;
    try {
      const naive: media.AVPlayer = await media.createAVPlayer();
      naiveHeld = true;
      this.tracker.acquire(TrackedResource.PLAYER);
      await naive.release();
      naiveHeld = false;
      this.tracker.release(TrackedResource.PLAYER);
      this.log.add(LogKind.STEP, 'log_naive_first');
      await naive.release();
      this.log.add(LogKind.STEP, 'log_naive_second_unexpected');
    } catch (error) {
      this.reportError(error as BusinessError);
    } finally {
      if (naiveHeld) {
        this.tracker.release(TrackedResource.PLAYER);
      }
    }

    // Part B: guarded. Two cleanup paths run at the same time and share one release run.
    this.log.add(LogKind.STEP, 'log_guarded_title');
    const session = new PlaybackSession(this.context,
      new PlaybackSource(SourceKind.RAWFILE, RAW_VALID_AUDIO), this.log, this.tracker);
    this.active.add(session);
    try {
      await session.open();
      await session.play(SHORT_PLAYBACK_MS);
    } catch (error) {
      this.reportError(error as BusinessError);
    } finally {
      // e.g. user taps Stop while an error callback also triggers cleanup.
      await Promise.all([session.release(), session.release()]);
      this.active.delete(session);
    }
  }

  // ---------- Scenario 5: record, then play the recording ----------

  private async runRecordAndPlay(): Promise<void> {
    if (!(await this.checkMicrophone())) {
      return;
    }
    const recorder = new RecordingSession(this.context, this.log, this.tracker, RECORD_SAMPLE_RATE);
    this.active.add(recorder);
    let recorded = false;
    try {
      await recorder.open();
      await recorder.record(RECORD_DEMO_MS);
      await recorder.stop();
      recorded = true;
    } catch (error) {
      this.reportError(error as BusinessError);
    } finally {
      // The recorder must be fully released before another object opens the same file.
      await recorder.release();
      this.active.delete(recorder);
    }
    if (recorded) {
      await this.runPlayback(new PlaybackSource(SourceKind.SANDBOX_FILE, RECORD_FILE_NAME), RECORD_DEMO_MS);
    }
  }

  // ---------- Scenario 6: recording fails after the output file exists ----------

  private async runFailedRecording(): Promise<void> {
    if (!(await this.checkMicrophone())) {
      return;
    }
    const recorder = new RecordingSession(this.context, this.log, this.tracker, INVALID_SAMPLE_RATE);
    this.active.add(recorder);
    try {
      await recorder.open();
      await recorder.record(RECORD_DEMO_MS);
      await recorder.stop();
    } catch (error) {
      this.reportError(error as BusinessError);
    } finally {
      await recorder.release();
      this.active.delete(recorder);
    }
    this.verifyFileRemoved(recorder.filePath);
  }

  // ---------- Helpers ----------

  private async checkMicrophone(): Promise<boolean> {
    let granted = false;
    try {
      granted = await PermissionHelper.ensureMicrophone(this.context);
    } catch (error) {
      this.reportError(error as BusinessError);
    }
    // Checked before anything is created: a denial leaves nothing to clean up.
    this.log.add(granted ? LogKind.STEP : LogKind.ERROR,
      granted ? 'log_permission_granted' : 'log_permission_denied');
    return granted;
  }

  private verifyFileRemoved(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        this.log.add(LogKind.ERROR, 'log_partial_still_there');
      } else {
        this.log.add(LogKind.RESULT, 'log_partial_gone_verified');
      }
    } catch (error) {
      this.reportError(error as BusinessError);
    }
  }

  private reportError(err: BusinessError): void {
    this.log.add(LogKind.ERROR, 'log_operation_failed', err.code, err.message ?? '');
    const hint = this.hintFor(err.code);
    if (hint.length > 0) {
      this.log.add(LogKind.STEP, hint);
    }
  }

  private hintFor(code: number): string {
    switch (code) {
      case ERR_INVALID_RAWFILE_PATH:
        return 'hint_missing_rawfile';
      case ERR_UNSUPPORTED_FORMAT:
        return 'hint_unsupported_format';
      case ERR_OPERATION_NOT_ALLOWED:
        return 'hint_operation_not_allowed';
      case ERR_INVALID_PARAMETER:
        return 'hint_invalid_parameter';
      case ERR_PERMISSION_DENIED:
        return 'hint_permission';
      case ERR_STATE_TIMEOUT:
        return 'hint_state_timeout';
      case ERR_SESSION_RELEASED:
        return 'hint_session_released';
      case ERR_ERROR_STATE:
        return 'hint_error_state';
      default:
        return '';
    }
  }
}
