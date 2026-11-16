import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, ErrorCallback } from '@kit.BasicServicesKit';
import { CleanupLog, LogKind } from '../model/CleanupLog';
import { ResourceTracker, TrackedResource } from '../model/ResourceTracker';
import { CleanupError, Releasable } from '../model/CleanupError';
import {
  ERR_SESSION_RELEASED,
  FD_URL_PREFIX,
  PATH_SEPARATOR,
  RECORD_AUDIO_BITRATE,
  RECORD_AUDIO_CHANNELS,
  RECORD_FILE_NAME,
  RecorderState
} from '../common/Constants';
import { delay } from '../common/TimeUtils';

/**
 * Owns one AVRecorder, the output file fd, and the output file itself.
 *
 * Cleanup order: recorder -> fd -> file.
 * If recording did not finish with a successful stop(), the output file is incomplete
 * and is deleted, so a failed recording never leaves a broken file on disk.
 */
export class RecordingSession implements Releasable {
  private context: common.UIAbilityContext;
  private log: CleanupLog;
  private tracker: ResourceTracker;
  private sampleRate: number;
  private recorder: media.AVRecorder | undefined = undefined;
  private fileFd: number = -1;
  private fileCreated: boolean = false;
  private completed: boolean = false;
  private releasePromise: Promise<void> | undefined = undefined;
  readonly filePath: string;

  constructor(context: common.UIAbilityContext, log: CleanupLog, tracker: ResourceTracker, sampleRate: number) {
    this.context = context;
    this.log = log;
    this.tracker = tracker;
    this.sampleRate = sampleRate;
    this.filePath = context.filesDir + PATH_SEPARATOR + RECORD_FILE_NAME;
  }

  /** Creates the recorder, opens the output file and prepares. Throws on any failure; the caller cleans up. */
  async open(): Promise<void> {
    const recorder = await media.createAVRecorder();
    if (this.isReleasing()) {
      await recorder.release();
      throw new CleanupError(ERR_SESSION_RELEASED, 'released during open');
    }
    this.recorder = recorder;
    this.tracker.acquire(TrackedResource.RECORDER);
    this.log.add(LogKind.STEP, 'log_recorder_created');
    recorder.on('stateChange', this.onStateChange);
    recorder.on('error', this.onError);

    const file = await fileIo.open(this.filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    if (this.isReleasing()) {
      await fileIo.close(file);
      fileIo.unlinkSync(this.filePath);
      throw new CleanupError(ERR_SESSION_RELEASED, 'released during open');
    }
    this.fileFd = file.fd;
    this.fileCreated = true;
    this.tracker.acquire(TrackedResource.FILE_FD);
    this.log.add(LogKind.STEP, 'log_record_file_opened', file.fd);

    // The output file now exists on disk. If prepare() fails below, release() deletes it.
    await this.requireRecorder().prepare(this.buildConfig(file.fd));
    this.log.add(LogKind.STEP, 'log_recorder_prepared');
  }

  async record(durationMs: number): Promise<void> {
    await this.requireRecorder().start();
    this.log.add(LogKind.STEP, 'log_recording', durationMs);
    await delay(durationMs);
  }

  /** Only a successful stop() produces a complete file. */
  async stop(): Promise<void> {
    const recorder = this.requireRecorder();
    const state: string = recorder.state;
    if (state === RecorderState.STARTED || state === RecorderState.PAUSED) {
      await recorder.stop();
      this.completed = true;
      this.log.add(LogKind.STEP, 'log_recorder_stopped');
    }
  }

  release(): Promise<void> {
    if (this.releasePromise !== undefined) {
      this.log.add(LogKind.CLEANUP, 'log_release_reused');
      return this.releasePromise;
    }
    this.releasePromise = this.doRelease();
    return this.releasePromise;
  }

  private async doRelease(): Promise<void> {
    // Step 1: listeners and recorder.
    const recorder = this.recorder;
    this.recorder = undefined;
    if (recorder !== undefined) {
      recorder.off('stateChange', this.onStateChange);
      recorder.off('error', this.onError);
      this.log.add(LogKind.CLEANUP, 'log_recorder_listeners_removed');
      try {
        const state: string = recorder.state;
        if (state !== RecorderState.RELEASED) {
          await recorder.release();
        }
        this.log.add(LogKind.CLEANUP, 'log_recorder_released');
      } catch (error) {
        const err = error as BusinessError;
        this.log.add(LogKind.ERROR, 'log_release_failed', err.code, err.message ?? '');
      } finally {
        this.tracker.release(TrackedResource.RECORDER);
      }
    } else {
      this.log.add(LogKind.CLEANUP, 'log_no_recorder');
    }

    // Step 2: the output fd, after the recorder that writes to it is gone.
    if (this.fileFd >= 0) {
      try {
        await fileIo.close(this.fileFd);
        this.log.add(LogKind.CLEANUP, 'log_record_fd_closed');
      } catch (error) {
        const err = error as BusinessError;
        this.log.add(LogKind.ERROR, 'log_release_failed', err.code, err.message ?? '');
      } finally {
        this.fileFd = -1;
        this.tracker.release(TrackedResource.FILE_FD);
      }
    } else {
      this.log.add(LogKind.CLEANUP, 'log_fd_skip');
    }

    // Step 3: the output file. Keep it only if recording completed.
    if (!this.fileCreated) {
      return;
    }
    if (this.completed) {
      this.log.add(LogKind.CLEANUP, 'log_record_kept');
      return;
    }
    try {
      fileIo.unlinkSync(this.filePath);
      this.log.add(LogKind.CLEANUP, 'log_partial_deleted');
    } catch (error) {
      const err = error as BusinessError;
      this.log.add(LogKind.ERROR, 'log_release_failed', err.code, err.message ?? '');
    } finally {
      this.fileCreated = false;
    }
  }

  private buildConfig(fd: number): media.AVRecorderConfig {
    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile: {
        audioBitrate: RECORD_AUDIO_BITRATE,
        audioChannels: RECORD_AUDIO_CHANNELS,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: this.sampleRate,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4A
      } as media.AVRecorderProfile,
      url: FD_URL_PREFIX + fd.toString()
    };
    return config;
  }

  private onStateChange: media.OnAVRecorderStateChangeHandler =
    (state: media.AVRecorderState, reason: media.StateChangeReason): void => {
      const current: string = state;
      this.log.add(LogKind.STEP, 'log_recorder_state', current);
      if (current === RecorderState.ERROR) {
        this.log.add(LogKind.CLEANUP, 'log_error_state_release');
        this.release();
      }
    };

  private onError: ErrorCallback = (error: BusinessError): void => {
    this.log.add(LogKind.ERROR, 'log_recorder_error', error.code, error.message ?? '');
  };

  private isReleasing(): boolean {
    return this.releasePromise !== undefined;
  }

  private requireRecorder(): media.AVRecorder {
    if (this.recorder === undefined) {
      throw new CleanupError(ERR_SESSION_RELEASED, 'recorder released');
    }
    return this.recorder;
  }
}
