// 自绘确认弹窗（v2.9）
// 用户要求：删除确认不要用系统 AlertDialog，要自己画，样式参照「个人工作台」的 .cf 弹窗：
//   .cf-overlay  rgba(23,52,80,.26) 遮罩 + 居中
//   .cf         白卡 / 1px #EAF2F9 / 圆角 22 / 大阴影
//   .cf-x       右上角 28×28 关闭钮（#F4F9FD / #8FA2B3）
//   .cf-ico     46×46 圆角 15 图标块（danger #FDEDEA/#D2795C，普通 #E9F7F6/#1F9E9A）
//   .cf-title   16.5px 粗体 #1D2A38
//   .cf-desc    12px #78899C 行高 21
//   .cf-acts    两个 38px 按钮：取消 #F5FAFD/#E6EFF8/#5E7183，确认 #3AC8C2 或 danger #E89079
//
// 用法（v2.9 实际在用）：本组件只当「弹窗内容」，由 utils/Confirm.ets 统一打开。
//   1) 页面里写一个 @Builder confirmBuilder()，里面渲染 ConfirmDialog
//   2) 点删除时调 Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); }, 标题, 说明, '删除', 回调)
//   3) 卡片上的 onConfirm → Confirm.confirm(this.getUIContext())；onCancel → Confirm.cancel(this.getUIContext())
//   为什么绕 openCustomDialog：删除按钮在 bindSheet 弹层里时，页面级遮罩盖不住 sheet，
//   openCustomDialog 是系统级弹窗层，和系统 AlertDialog 同级，能压在 sheet 上面。
import { sym } from './Icon';
import { onFill, tc, tk } from '../utils/Theme';

@Component
export struct ConfirmDialog {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop visible: boolean = false;
  @Prop title: string = '';
  @Prop desc: string = '';
  @Prop danger: boolean = true;
  @Prop confirmText: string = '删除';
  @Prop cancelText: string = '取消';
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  build() {
    if (this.visible) {
      Stack() {
        // 遮罩：点一下就取消
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(23,52,80,0.26)')
          .onClick(() => { this.onCancel(); })

        // 卡片层
        Column() {
          this.card()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
    }
  }

  @Builder card() {
    Column() {
      // 右上角关闭
      Row() {
        Blank()
        SymbolGlyph(sym('close'))
          .fontSize(14)
          .fontColor([tc(this.dark, '#8FA2B3', 1)])
          .width(28)
          .height(28)
          .borderRadius(9)
          .backgroundColor(tc(this.dark, '#F4F9FD', 0))
          .onClick(() => { this.onCancel(); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      // 图标
      Row() {
        SymbolGlyph(sym(this.danger ? 'trash' : 'bulb'))
          .fontSize(19)
          .fontColor([this.danger ? tc(this.dark, '#D2795C', 1) : tc(this.dark, '#1F9E9A', 1)])
      }
      .width(46)
      .height(46)
      .borderRadius(15)
      .backgroundColor(this.danger ? tc(this.dark, '#FDEDEA', 0) : tc(this.dark, '#E9F7F6', 0))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 2, bottom: 14 })

      // 标题
      Text(this.title)
        .fontSize(16.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(tc(this.dark, '#1D2A38', 1))
        .textAlign(TextAlign.Center)
        .width('100%')

      // 说明
      if (this.desc.length > 0) {
        Text(this.desc)
          .fontSize(12)
          .fontColor(tc(this.dark, '#78899C', 1))
          .lineHeight(21)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 6 })
      }

      // 两个按钮
      Row({ space: 9 }) {
        Text(this.cancelText)
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(tc(this.dark, '#5E7183', 1))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(38)
          .borderRadius(11)
          .backgroundColor(tc(this.dark, '#F5FAFD', 0))
          .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6EFF8', 2), 2) })
          .onClick(() => { this.onCancel(); })

        Text(this.confirmText)
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(onFill(this.dark))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(38)
          .borderRadius(11)
          .backgroundColor(this.danger ? tc(this.dark, '#E89079', 0) : tc(this.dark, '#3AC8C2', 0))
          .onClick(() => { this.onConfirm(); })
      }
      .width('100%')
      .margin({ top: 20 })
    }
    .width('88%')
    .constraintSize({ maxWidth: 380 })
    .padding({ left: 26, right: 26, top: 14, bottom: 20 })
    .borderRadius(22)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#EAF2F9', 2), 2) })
    .shadow({ radius: 30, color: 'rgba(23,52,80,0.24)', offsetX: 0, offsetY: 14 })
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }
}
