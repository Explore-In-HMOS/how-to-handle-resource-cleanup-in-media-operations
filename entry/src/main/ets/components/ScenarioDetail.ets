import { common } from '@kit.AbilityKit';
import { ArcList, ArcListItem, ArcListAttribute, ArcListItemAttribute, LengthMetrics } from '@kit.ArkUI';
import { CleanupLog, LogEntry, LogKind } from '../model/CleanupLog';
import { ResourceSnapshot, ResourceTracker } from '../model/ResourceTracker';
import { SCENARIOS, ScenarioItem } from '../model/Scenario';
import { ScenarioRunner } from '../service/ScenarioRunner';
import { ResourceChip } from './ResourceChip';

enum RunPhase {
  READY = 0,
  RUNNING = 1,
  CLEAN = 2,
  LEAK = 3
}

/**
 * One scenario screen: what it tests, live resource counters, Run button, result banner, tagged log.
 * Leaving this screen mid-run releases every active session (aboutToDisappear).
 */
@Component
export struct ScenarioDetail {
  item: ScenarioItem = SCENARIOS[0];
  @State logEntries: LogEntry[] = [];
  @State players: number = 0;
  @State recorders: number = 0;
  @State rawFds: number = 0;
  @State fileFds: number = 0;
  @State phase: RunPhase = RunPhase.READY;
  @State leakCount: number = 0;
  private runner: ScenarioRunner | undefined = undefined;
  private cleanupLog: CleanupLog | undefined = undefined;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.cleanupLog = new CleanupLog(context, (entries: LogEntry[]) => {
      this.logEntries = entries;
    });
    const tracker = new ResourceTracker((snapshot: ResourceSnapshot) => {
      this.players = snapshot.players;
      this.recorders = snapshot.recorders;
      this.rawFds = snapshot.rawFds;
      this.fileFds = snapshot.fileFds;
    });
    this.runner = new ScenarioRunner(context, this.cleanupLog, tracker);
  }

  aboutToDisappear(): void {
    this.runner?.releaseAll();
  }

  private async run(): Promise<void> {
    if (this.phase === RunPhase.RUNNING || this.runner === undefined) {
      return;
    }
    this.cleanupLog?.clear();
    this.phase = RunPhase.RUNNING;
    let open = 0;
    try {
      open = await this.runner.run(this.item);
    } finally {
      this.leakCount = open;
      this.phase = open === 0 ? RunPhase.CLEAN : RunPhase.LEAK;
      this.scroller.scrollToIndex(0);
    }
  }

  private tagFor(kind: LogKind): Resource {
    switch (kind) {
      case LogKind.CLEANUP:
        return $r('app.string.tag_cleanup');
      case LogKind.ERROR:
        return $r('app.string.tag_error');
      case LogKind.RESULT:
        return $r('app.string.tag_result');
      default:
        return $r('app.string.tag_step');
    }
  }

  private colorFor(kind: LogKind): Resource {
    switch (kind) {
      case LogKind.CLEANUP:
        return $r('app.color.log_cleanup');
      case LogKind.ERROR:
        return $r('app.color.log_error');
      case LogKind.RESULT:
        return $r('app.color.log_result');
      default:
        return $r('app.color.log_step');
    }
  }

  @Builder
  ResultBanner() {
    Text(this.phase === RunPhase.CLEAN ? $r('app.string.result_clean') :
      $r('app.string.result_leak', this.leakCount))
      .fontSize($r('app.float.card_title_font'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .textAlign(TextAlign.Center)
      .width('80%')
      .padding($r('app.float.card_padding'))
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor(this.phase === RunPhase.CLEAN ? $r('app.color.result_clean_bg') :
        $r('app.color.result_leak_bg'))
  }

  @Builder
  LogRow(entry: LogEntry) {
    Row({ space: 6 }) {
      Text(this.tagFor(entry.kind))
        .fontSize($r('app.float.tag_font'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colorFor(entry.kind))
        .width($r('app.float.tag_width'))
      Text(entry.message)
        .fontSize($r('app.float.log_font'))
        .fontColor(entry.kind === LogKind.STEP ? $r('app.color.log_step') : this.colorFor(entry.kind))
        .layoutWeight(1)
    }
    .width('84%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    ArcList({ initialIndex: 0, scroller: this.scroller }) {
      ArcListItem() {
        Column({ space: 4 }) {
          Text(this.item.title)
            .fontSize($r('app.float.title_font'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.item.detail)
            .fontSize($r('app.float.card_summary_font'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .width('80%')
        }
        .width('100%')
        .margin({ top: $r('app.float.top_inset') })
      }

      ArcListItem() {
        Column({ space: 4 }) {
          Text($r('app.string.section_resources'))
            .fontSize($r('app.float.section_font'))
            .fontColor($r('app.color.text_secondary'))
          Row() {
            ResourceChip({ label: $r('app.string.label_player'), count: this.players })
            ResourceChip({ label: $r('app.string.label_recorder'), count: this.recorders })
          }
          .width('80%')
          .justifyContent(FlexAlign.SpaceBetween)

          Row() {
            ResourceChip({ label: $r('app.string.label_rawfd'), count: this.rawFds })
            ResourceChip({ label: $r('app.string.label_fd'), count: this.fileFds })
          }
          .width('80%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
      }

      if (this.phase === RunPhase.CLEAN || this.phase === RunPhase.LEAK) {
        ArcListItem() {
          Column() {
            this.ResultBanner()
          }
          .width('100%')
        }
      }

      ArcListItem() {
        Button(this.phase === RunPhase.RUNNING ? $r('app.string.running') :
          (this.phase === RunPhase.READY ? $r('app.string.run') : $r('app.string.run_again')))
          .width('70%')
          .height($r('app.float.button_height'))
          .fontSize($r('app.float.button_font'))
          .fontColor($r('app.color.button_text'))
          .backgroundColor($r('app.color.button_bg'))
          .enabled(this.phase !== RunPhase.RUNNING)
          .opacity(this.phase === RunPhase.RUNNING ? 0.5 : 1)
          .onClick(() => {
            this.run();
          })
      }
      .width('100%')

      ArcListItem() {
        Text(this.logEntries.length === 0 ? $r('app.string.log_empty') : $r('app.string.section_log'))
          .fontSize($r('app.float.section_font'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      ForEach(this.logEntries, (entry: LogEntry) => {
        ArcListItem() {
          this.LogRow(entry)
        }
        .width('100%')
      }, (entry: LogEntry) => entry.id.toString())

      ArcListItem() {

      }
    }
    .space(LengthMetrics.vp(6))
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .focusable(true)
    .focusOnTouch(true)
    .defaultFocus(true)
  }
}