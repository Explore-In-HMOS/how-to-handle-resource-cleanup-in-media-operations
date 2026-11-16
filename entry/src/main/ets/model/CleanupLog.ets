import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';
import { MAX_LOG_ENTRIES } from '../common/Constants';

export enum LogKind {
  STEP = 0,
  CLEANUP = 1,
  ERROR = 2,
  RESULT = 3
}

export class LogEntry {
  id: number;
  kind: LogKind;
  message: string;

  constructor(id: number, kind: LogKind, message: string) {
    this.id = id;
    this.kind = kind;
    this.message = message;
  }
}

export type LogListener = (entries: LogEntry[]) => void;

export class CleanupLog {
  private context: common.Context;
  private listener: LogListener;
  private entries: LogEntry[] = [];
  private nextId: number = 0;

  constructor(context: common.Context, listener: LogListener) {
    this.context = context;
    this.listener = listener;
  }

  add(kind: LogKind, resName: string, ...args: Array<string | number>): void {
    let message: string = resName;
    try {
      message = this.context.resourceManager.getStringByNameSync(resName, ...args);
    } catch (error) {
      Logger.error(`Missing log string: ${resName}`);
    }
    if (kind === LogKind.ERROR) {
      Logger.error(message);
    } else {
      Logger.info(message);
    }
    const next: LogEntry[] = this.entries.slice(Math.max(0, this.entries.length - MAX_LOG_ENTRIES + 1));
    next.push(new LogEntry(this.nextId++, kind, message));
    this.entries = next;
    this.listener(this.entries);
  }

  clear(): void {
    this.entries = [];
    this.listener(this.entries);
  }
}
