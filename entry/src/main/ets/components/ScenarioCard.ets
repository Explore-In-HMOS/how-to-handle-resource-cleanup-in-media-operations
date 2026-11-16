import { SCENARIOS, ScenarioItem } from '../model/Scenario';

/** Home list entry: number, title and a one-line summary of what the scenario proves. */
@Component
export struct ScenarioCard {
  item: ScenarioItem = SCENARIOS[0];
  onSelect: () => void = () => {
  };

  build() {
    Row({ space: 8 }) {
      Text((this.item.id + 1).toString())
        .fontSize($r('app.float.number_font'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.number_text'))
        .textAlign(TextAlign.Center)
        .width($r('app.float.number_size'))
        .height($r('app.float.number_size'))
        .borderRadius($r('app.float.number_radius'))
        .backgroundColor($r('app.color.number_bg'))

      Column({ space: 2 }) {
        Text(this.item.title)
          .fontSize($r('app.float.card_title_font'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.item.summary)
          .fontSize($r('app.float.card_summary_font'))
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('84%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_bg'))
    .onClick(() => this.onSelect())
  }
}
