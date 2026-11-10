// 任务状态圈（v2.8）
// 待办 = 白色空心圈（工作台 globals.css: .tcard .check）
// 进行中 = 半色（浅琥珀底 + 琥珀边 + 中心半透明点）
// 已完成 = 全色（薄荷绿实心 + 白勾）（工作台 .tcard.done .check）
// 点击用 TapGesture 而不是 onClick：既不会被卡片自己的 onClick 抢走，
// 也不会顺带弹出编辑框（ArkTS 里 onClick 会冒泡到父容器）。
import { C, onFill, tc, tk } from '../utils/Theme';
import { sym } from './Icon';

@Component
export struct StatusDot {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop status: string = 'todo';
  // 不能叫 size：ArkUI 已有同名通用属性 .size()，@Prop 会和它撞类型
  @Prop dotSize: number = 16;
  onTap: () => void = () => {};

  build() {
    Column() {
      if (this.status === 'done') {
        // v4.23：华为 UX 2.1.4.3.2 要求图标 >= 8vp（推荐 12vp），
        // 勾的比例从 0.6 提到 0.7 => dotSize 20 时勾 14vp，墨迹 >= 8.6vp。
        SymbolGlyph(sym('check')).fontSize(this.dotSize * 0.7).fontColor([onFill(this.dark)])
      } else if (this.status === 'doing') {
        Row()
          .width(this.dotSize * 0.44)
          .height(this.dotSize * 0.44)
          .borderRadius(this.dotSize * 0.22)
          .backgroundColor(tk(this.dark, 'doing'))
          .opacity(0.55)
      }
    }
    .width(this.dotSize)
    .height(this.dotSize)
    .borderRadius(this.dotSize / 2)
    .backgroundColor(this.status === 'done' ? tk(this.dark, 'done') : (this.status === 'doing' ? tk(this.dark, 'doingSoft') : tk(this.dark, 'card')))
    .border({
      width: 1.5,
      color: this.status === 'done' ? tk(this.dark, 'done') : (this.status === 'doing' ? tk(this.dark, 'doingLine') : tk(this.dark, 'checkRing'))
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .gesture(
      TapGesture({ count: 1 })
        .onAction(() => { this.onTap(); })
    )
  }
}
