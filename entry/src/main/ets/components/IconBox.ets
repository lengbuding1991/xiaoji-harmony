// 一个带底色的圆角小图标块（工作台 .kpi-ico / .mi / .tsi 都是这个形状）
import { sym } from './Icon';
import { catBg, tk } from '../utils/Theme';

@Component
export struct IconBox {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop name: string = 'home';
  @Prop boxSize: number = 30;
  @Prop iconSize: number = 15;
  @Prop radius: number = 10;
  @Prop bg: string = '';
  @Prop fg: string = '';

  build() {
    Row() {
      SymbolGlyph(sym(this.name))
        .fontSize(this.iconSize)
        .fontColor([this.fg.length > 0 ? this.fg : tk(this.pal, 'work')])
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(this.radius)
    .backgroundColor(this.bg.length > 0 ? this.bg : catBg(this.pal, 'work'))
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }
}
