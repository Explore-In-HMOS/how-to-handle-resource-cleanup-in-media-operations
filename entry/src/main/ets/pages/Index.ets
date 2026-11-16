import { ArcList, ArcListItem, ArcListAttribute, ArcListItemAttribute, LengthMetrics } from '@kit.ArkUI';
import { SCENARIOS, ScenarioItem } from '../model/Scenario';
import { ScenarioCard } from '../components/ScenarioCard';
import { ScenarioDetail } from '../components/ScenarioDetail';
import { SCENARIO_PAGE } from '../common/Constants';

@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();

  @Builder
  pageMap(name: string, param: Object) {
    if (name === SCENARIO_PAGE) {
      NavDestination() {
        ScenarioDetail({ item: param as ScenarioItem })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_bg'))
    }
  }

  build() {
    Navigation(this.pathStack) {
      ArcList({ initialIndex: 0 }) {
        ArcListItem() {
          Column({ space: 4 }) {
            Text($r('app.string.page_title'))
              .fontSize($r('app.float.title_font'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.home_subtitle'))
              .fontSize($r('app.float.card_summary_font'))
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .width('74%')
          }
          .width('100%')
          .margin({ top: $r('app.float.top_inset') })
        }

        ForEach(SCENARIOS, (item: ScenarioItem) => {
          ArcListItem() {
            ScenarioCard({
              item: item,
              onSelect: () => {
                this.pathStack.pushPathByName(SCENARIO_PAGE, item);
              }
            })
          }
          .width('100%')
        }, (item: ScenarioItem) => item.id.toString())

        ArcListItem() {

        }
      }
      .space(LengthMetrics.vp(8))
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'))
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
    }
    .hideTitleBar(true)
    .hideToolBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .backgroundColor($r('app.color.page_bg'))
  }
}
