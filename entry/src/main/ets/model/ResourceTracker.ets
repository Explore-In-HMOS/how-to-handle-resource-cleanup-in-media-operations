export enum TrackedResource {
  PLAYER = 0,
  RECORDER = 1,
  RAW_FD = 2,
  FILE_FD = 3
}

export class ResourceSnapshot {
  players: number = 0;
  recorders: number = 0;
  rawFds: number = 0;
  fileFds: number = 0;

  total(): number {
    return this.players + this.recorders + this.rawFds + this.fileFds;
  }

  copy(): ResourceSnapshot {
    const snapshot = new ResourceSnapshot();
    snapshot.players = this.players;
    snapshot.recorders = this.recorders;
    snapshot.rawFds = this.rawFds;
    snapshot.fileFds = this.fileFds;
    return snapshot;
  }
}

export type TrackerListener = (snapshot: ResourceSnapshot) => void;

export class ResourceTracker {
  private snapshot: ResourceSnapshot = new ResourceSnapshot();
  private listener: TrackerListener;

  constructor(listener: TrackerListener) {
    this.listener = listener;
  }

  acquire(resource: TrackedResource): void {
    this.adjust(resource, 1);
  }

  release(resource: TrackedResource): void {
    this.adjust(resource, -1);
  }

  current(): ResourceSnapshot {
    return this.snapshot.copy();
  }

  private adjust(resource: TrackedResource, delta: number): void {
    const next = this.snapshot.copy();
    switch (resource) {
      case TrackedResource.PLAYER:
        next.players += delta;
        break;
      case TrackedResource.RECORDER:
        next.recorders += delta;
        break;
      case TrackedResource.RAW_FD:
        next.rawFds += delta;
        break;
      case TrackedResource.FILE_FD:
        next.fileFds += delta;
        break;
      default:
        break;
    }
    this.snapshot = next;
    this.listener(next.copy());
  }
}
