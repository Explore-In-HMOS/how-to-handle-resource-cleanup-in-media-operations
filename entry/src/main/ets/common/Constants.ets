import { Permissions } from '@kit.AbilityKit';

// Navigation
export const SCENARIO_PAGE: string = 'ScenarioPage';

// Logging
export const LOG_DOMAIN: number = 0x0001;
export const LOG_TAG: string = 'MediaCleanup';
export const MAX_LOG_ENTRIES: number = 200;

// Media sources
export const RAW_VALID_AUDIO: string = 'sample_tone.wav';
export const RAW_MISSING_AUDIO: string = 'not_in_package.mp3';
export const RAW_CORRUPT_AUDIO: string = 'corrupt_audio.mp3';
export const RECORD_FILE_NAME: string = 'cleanup_recording.m4a';
export const FD_URL_PREFIX: string = 'fd://';
export const PATH_SEPARATOR: string = '/';

// Timing
export const PLAYBACK_DEMO_MS: number = 3000;
export const SHORT_PLAYBACK_MS: number = 1000;
export const RECORD_DEMO_MS: number = 3000;
export const STATE_WAIT_TIMEOUT_MS: number = 5000;

// Recording profile (values from the AVRecorder audio guide)
export const RECORD_AUDIO_BITRATE: number = 112000;
export const RECORD_AUDIO_CHANNELS: number = 2;
export const RECORD_SAMPLE_RATE: number = 48000;
// Deliberately invalid sample rate used by the failed-recording scenario
export const INVALID_SAMPLE_RATE: number = -1;

// Permissions
export const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

// System error codes handled in this codelab
export const ERR_PERMISSION_DENIED: number = 201;
export const ERR_INVALID_PARAMETER: number = 401;
export const ERR_OPERATION_NOT_ALLOWED: number = 5400102;
export const ERR_UNSUPPORTED_FORMAT: number = 5400106;
export const ERR_INVALID_RAWFILE_PATH: number = 9001005;

// App-defined error codes (negative so they never collide with system codes)
export const ERR_STATE_TIMEOUT: number = -1001;
export const ERR_SESSION_RELEASED: number = -1002;
export const ERR_ERROR_STATE: number = -1003;

// AVPlayer states (values of media.AVPlayerState)
export enum PlayerState {
  IDLE = 'idle',
  INITIALIZED = 'initialized',
  PREPARED = 'prepared',
  PLAYING = 'playing',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  STOPPED = 'stopped',
  RELEASED = 'released',
  ERROR = 'error'
}

// AVRecorder states (values of media.AVRecorderState)
export enum RecorderState {
  IDLE = 'idle',
  PREPARED = 'prepared',
  STARTED = 'started',
  PAUSED = 'paused',
  STOPPED = 'stopped',
  RELEASED = 'released',
  ERROR = 'error'
}
