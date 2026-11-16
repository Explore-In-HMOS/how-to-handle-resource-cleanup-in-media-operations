/** One live counter (Player / Rec / RawFd / Fd). Highlighted while the resource is held. */
@Component
export struct ResourceChip {
  @Prop label: ResourceStr = '';
  @Prop count: number = 0;

  build() {
    Row({ space: 4 }) {
      Text(this.label)
        .fontSize($r('app.float.chip_font'))
        .fontColor(this.count > 0 ? $r('app.color.chip_active_text') : $r('app.color.text_secondary'))
      Text(this.count.toString())
        .fontSize($r('app.float.chip_font'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.count > 0 ? $r('app.color.chip_active_text') : $r('app.color.text_primary'))
    }
    .justifyContent(FlexAlign.Center)
    .width('48%')
    .height($r('app.float.chip_height'))
    .borderRadius($r('app.float.chip_radius'))
    .backgroundColor(this.count > 0 ? $r('app.color.chip_active_bg') : $r('app.color.chip_bg'))
  }
}
