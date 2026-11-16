export enum ScenarioId {
  CLEAN_PLAYBACK = 0,
  MISSING_FILE = 1,
  CORRUPT_FILE = 2,
  DOUBLE_RELEASE = 3,
  RECORD_AND_PLAY = 4,
  FAILED_RECORDING = 5
}

export class ScenarioItem {
  id: ScenarioId;
  title: Resource;
  summary: Resource;
  detail: Resource;

  constructor(id: ScenarioId, title: Resource, summary: Resource, detail: Resource) {
    this.id = id;
    this.title = title;
    this.summary = summary;
    this.detail = detail;
  }
}

export const SCENARIOS: ScenarioItem[] = [
  new ScenarioItem(ScenarioId.CLEAN_PLAYBACK, $r('app.string.scenario_clean_playback'),
    $r('app.string.summary_clean_playback'), $r('app.string.detail_clean_playback')),
  new ScenarioItem(ScenarioId.MISSING_FILE, $r('app.string.scenario_missing_file'),
    $r('app.string.summary_missing_file'), $r('app.string.detail_missing_file')),
  new ScenarioItem(ScenarioId.CORRUPT_FILE, $r('app.string.scenario_corrupt_file'),
    $r('app.string.summary_corrupt_file'), $r('app.string.detail_corrupt_file')),
  new ScenarioItem(ScenarioId.DOUBLE_RELEASE, $r('app.string.scenario_double_release'),
    $r('app.string.summary_double_release'), $r('app.string.detail_double_release')),
  new ScenarioItem(ScenarioId.RECORD_AND_PLAY, $r('app.string.scenario_record_play'),
    $r('app.string.summary_record_play'), $r('app.string.detail_record_play')),
  new ScenarioItem(ScenarioId.FAILED_RECORDING, $r('app.string.scenario_failed_record'),
    $r('app.string.summary_failed_record'), $r('app.string.detail_failed_record'))
];
