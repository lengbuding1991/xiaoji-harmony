// 首启隐私弹窗（v4.7 · 上架准备）
//
// 应用市场审核要求：第一次打开 App 必须先弹隐私政策，用户点「同意」之后才能用。
// 所以这里不用系统的 AlertDialog（审核不认），用自己画的一张卡片，
// 样式跟「个人工作台」的 .cf 弹窗一致：
//   .cf-overlay  rgba(23,52,80,.42) 遮罩
//   .cf         白卡 / 圆角 22 / 大阴影 / maxWidth 420
//   .cf-ico     46×46 圆角 15 图标块（#E9F7F6 / #1F9E9A）
//   .cf-title   16.5px 粗体 #1D2A38
//   .cf-desc    12px #78899C 行高 21
//   按钮：同意 #3AC8C2，拒绝 #F5FAFD/#E6EFF8/#5E7183
import { sym } from './Icon';
import { onFill, tc, tk } from '../utils/Theme';

@Component
export struct PrivacyDialog {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop visible: boolean = false;
  /** 用户点了「同意并开始使用」 */
  onAgree: () => void = () => {};
  /** 用户点了「不同意」—— 直接退出 App */
  onDisagree: () => void = () => {};
  /** 用户点了《用户协议》《隐私政策》—— 打开协议正文页 */
  onViewPolicy: () => void = () => {};

  private readonly points: string[] = [
    '所有内容只存在这台手机上：不联网、不上传、不需要注册账号',
    '不收集姓名、手机号、位置等任何个人信息',
    '不申请任何系统权限：不开通知、不读设备标识、不在后台运行',
    '卸载 App 会一起删除数据，重要内容请先在设置里「复制备份」'
  ];

  build() {
    if (this.visible) {
      Stack() {
        // 遮罩：不可点掉（必须选同意或不同意）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(23,52,80,0.42)')

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
    }
  }

  @Builder
  card() {
    Column() {
      // 图标
      Row() {
        SymbolGlyph(sym('checkCircle'))
          .fontSize(19)
          .fontColor([tc(this.dark, '#1F9E9A', 1)])
      }
      .width(46)
      .height(46)
      .borderRadius(15)
      .backgroundColor(tc(this.dark, '#E9F7F6', 0))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      // 标题
      Text('欢迎使用小记')
        .fontSize(16.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(tc(this.dark, '#1D2A38', 1))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 12 })

      Text('在开始之前，请先了解这个 App 怎么对待你的数据')
        .fontSize(11.5)
        .fontColor(tc(this.dark, '#78899C', 1))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 5 })

      // 要点
      Column({ space: 8 }) {
        ForEach(this.points, (p: string) => {
          Row({ space: 8 }) {
            Row()
              .width(5).height(5).borderRadius(3)
              .backgroundColor(tc(this.dark, '#3AC8C2', 0))
              .margin({ top: 6 })
            Text(p)
              .fontSize(11)
              .fontColor(tc(this.dark, '#5C7086', 1))
              .lineHeight(17)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (p: string) => `pp-${p.slice(0, 6)}`)
      }
      .width('100%')
      .margin({ top: 14 })
      .alignItems(HorizontalAlign.Start)

      // 协议入口
      Text('《用户协议》《隐私政策》')
        .fontSize(11)
        .fontColor(tc(this.dark, '#1F9E9A', 1))
        .margin({ top: 14 })
        .onClick(() => { this.onViewPolicy(); })

      // 按钮
      Row({ space: 9 }) {
        Text('不同意并退出')
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(tc(this.dark, '#5E7183', 1))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(38)
          .borderRadius(11)
          .backgroundColor(tc(this.dark, '#F5FAFD', 0))
          .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6EFF8', 2), 2) })
          .onClick(() => { this.onDisagree(); })

        Text('同意并开始使用')
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(onFill(this.dark))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(38)
          .borderRadius(11)
          .backgroundColor(tc(this.dark, '#3AC8C2', 0))
          .onClick(() => { this.onAgree(); })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('88%')
    .constraintSize({ maxWidth: 420 })
    .padding({ left: 24, right: 24, top: 22, bottom: 20 })
    .borderRadius(22)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#EAF2F9', 2), 2) })
    .shadow({ radius: 30, color: 'rgba(23,52,80,0.26)', offsetX: 0, offsetY: 14 })
    .alignItems(HorizontalAlign.Center)
  }
}
