// 任务状态圈（v2.8；v5.0 加了「填色 + 弹一下」的动效）
// 待办 = 白色空心圈（工作台 globals.css: .tcard .check）
// 进行中 = 半色（浅琥珀底 + 琥珀边 + 中心半透明点）
// 已完成 = 全色（薄荷绿实心 + 白勾）（工作台 .tcard.done .check）
// 点击用 TapGesture 而不是 onClick：既不会被卡片自己的 onClick 抢走，
// 也不会顺带弹出编辑框（ArkTS 里 onClick 会冒泡到父容器）。
//
// v5.0 动效说明：
//   ① 圈底颜色从「空心白」变成「实心绿」时是渐变过去的，不是啪一下换掉
//      —— 靠 .animation() 的隐式动画（底色那一层单独一个节点）。
//   ② 勾出现时圈会「弹」一下（1.28 倍再收回 1），靠 animateTo 显式插值。
//   ③ 两个动画分开放在两层节点上：底色层用 .animation()，图形层用 animateTo，
//      同一个节点上同时用容易互相抢。
import { onFill, tc, tk } from '../utils/Theme';
import { sym } from './Icon';

@Component
export struct StatusDot {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  // @Watch：状态一变就播一次弹跳动画
  @Prop @Watch('onStatusChanged') status: string = 'todo';
  // 不能叫 size：ArkUI 已有同名通用属性 .size()，@Prop 会和它撞类型
  @Prop dotSize: number = 16;
  onTap: () => void = () => {};

  // v5.0：图形层的弹跳缩放（@State，属性里直接读才会重画）
  @State pop: number = 1;
  private popTimer: number = -1;

  aboutToDisappear(): void {
    if (this.popTimer !== -1) {
      clearTimeout(this.popTimer);
      this.popTimer = -1;
    }
  }

  onStatusChanged(): void {
    if (this.popTimer !== -1) {
      clearTimeout(this.popTimer);
    }
    // 先瞬间放大（这一层没有 .animation()，所以是瞬时的）
    this.pop = 1.28;
    // 停 60ms 再用 animateTo 收回去 ⇒ 看起来是「弹了一下」
    this.popTimer = setTimeout(() => {
      this.popTimer = -1;
      this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
        this.pop = 1;
      });
    }, 60);
  }

  build() {
    // v5.15 可访问性：圈本身还是原来那么小（dotSize），外面套一层 40×40 的透明热区，
    //   手指点得到的范围 ≥40×40（原来只有 20 左右，手指很难点中）。
    Row() {
      Stack() {
        // ── 底色层：颜色渐变靠 .animation() ──
        Column()
          .width(this.dotSize)
          .height(this.dotSize)
          .borderRadius(this.dotSize / 2)
          .backgroundColor(this.status === 'done' ? tk(this.pal, 'done') : (this.status === 'doing' ? tk(this.pal, 'doingSoft') : tk(this.pal, 'card')))
          .border({
            width: 1.5,
            color: this.status === 'done' ? tk(this.pal, 'done') : (this.status === 'doing' ? tk(this.pal, 'doingLine') : tk(this.pal, 'checkRing'))
          })
          .animation({ duration: 220, curve: Curve.EaseOut })

        // ── 图形层：弹跳靠 animateTo ──
        Column() {
          if (this.status === 'done') {
            // v4.23：华为 UX 2.1.4.3.2 要求图标 >= 8vp（推荐 12vp），
            // 勾的比例从 0.6 提到 0.7 => dotSize 20 时勾 14vp，墨迹 >= 8.6vp。
            SymbolGlyph(sym('check')).fontSize(this.dotSize * 0.7).fontColor([onFill(this.pal)])
          } else if (this.status === 'doing') {
            Row()
              .width(this.dotSize * 0.44)
              .height(this.dotSize * 0.44)
              .borderRadius(this.dotSize * 0.22)
              .backgroundColor(tk(this.pal, 'doing'))
              .opacity(0.55)
          }
        }
        .width(this.dotSize)
        .height(this.dotSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .scale({ x: this.pop, y: this.pop })
      }
      .width(this.dotSize)
      .height(this.dotSize)
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .gesture(
      TapGesture({ count: 1 })
        .onAction(() => { this.onTap(); })
    )
    // v5.15：告诉读屏软件「现在是什么状态、点一下会变成什么」
    .accessibilityText(this.a11yLabel())
  }

  /** v5.15：状态圈的无障碍文案 */
  private a11yLabel(): string {
    if (this.status === 'done') { return '已完成，点一下改回待办'; }
    if (this.status === 'doing') { return '进行中，点一下标记为已完成'; }
    return '待办，点一下标记为已完成';
  }
}
