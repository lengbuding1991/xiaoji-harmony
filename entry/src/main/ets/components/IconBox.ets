// 一个带底色的圆角小图标块（工作台 .kpi-ico / .mi / .tsi 都是这个形状）
import { sym } from './Icon';

@Component
export struct IconBox {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop name: string = 'home';
  @Prop boxSize: number = 30;
  @Prop iconSize: number = 15;
  @Prop radius: number = 10;
  @Prop bg: string = '#E8F2FC';
  @Prop fg: string = '#276AA4';

  build() {
    Row() {
      SymbolGlyph(sym(this.name))
        .fontSize(this.iconSize)
        .fontColor([this.fg])
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(this.radius)
    .backgroundColor(this.bg)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }
}
