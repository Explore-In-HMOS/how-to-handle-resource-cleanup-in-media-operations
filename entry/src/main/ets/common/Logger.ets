import { hilog } from '@kit.PerformanceAnalysisKit';
import { LOG_DOMAIN, LOG_TAG } from './Constants';

export class Logger {
  static info(message: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }
}
