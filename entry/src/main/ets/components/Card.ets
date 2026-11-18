// 卡片：严格对齐工作台的 .card
//   background:#fff; border:1px solid #EDF4FA; border-radius:20px; box-shadow:var(--sh)
//   .c-head  padding: 13px 14px 0
//   .c-body  padding: 10px 14px 14px
//
// ⚠️ 两个硬约束（踩过坑，别改回去）：
// 1. 不能有名为 padding / size 的 @Prop —— 会和 CustomComponent 基类方法撞名。
// 2. 只能有一个 @BuilderParam —— 尾随闭包语法 `Card({...}) { ... }` 要求「有且仅有一个」
//    @BuilderParam，多一个就报 10905102。所以头部右侧换成 headMode + 回调。
//
// v4.6：宽屏同一行的两块卡要一样高（网页端 .home-grid 的 align-items:stretch）。
// ⚠️ 不能用 height('100%') 撑满：ArkUI 的百分比高度会向上冒泡到「最近的有确定高度的
//    祖先」（这里是 Scroll/视口），卡片会被拉到视口高度、卡内出现大片空白。
//    正确做法 = 卡上报内容高度（onContentHeight），父级取同行最大值回填 fixedHeight。
import { cardShadow, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from './Icon';

/**
 * 头部右侧控件：
 *   ''        无
 *   'link'    「查看全部 →」胶囊链接      （headText + onHead）
 *   'text'    纯文字链接                  （headText + onHead）
 *   'arrows'  左右箭头                    （onPrev / onNext）
 *   'add'     「＋ 新任务」胶囊按钮        （headText + onHead）
 */
@Component
export struct Card {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop title: string = '';
  @Prop sub: string = '';
  @Prop headMode: string = '';
  @Prop headText: string = '';
  @Prop bodyPadTop: number = S.bodyPadT;
  @Prop bodyPadBottom: number = S.bodyPadB;
  // 宽屏同一行的两块卡要一样高（网页端 .home-grid 的 align-items:stretch）。
  // 不能用 height('100%')：ArkUI 会把百分比冒泡到 Scroll/视口，卡片被拉到视口高。
  // 做法 = 上报内容高度（onContentHeight），由父级算出该行的最大高度后回填 fixedHeight。
  @Prop fixedHeight: number = 0;
  // v5.0：入场动画的延迟（毫秒）。>0 时这张卡先透明着，等一会儿再「浮现」。
  //      父级按顺序给不同 delay，就是「逐个浮现」的效果。
  @Prop appearDelay: number = 0;
  onHead: () => void = () => {};
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onContentHeight: (h: number) => void = () => {};
  @BuilderParam content: () => void = this.none;

  // v5.0：入场动画状态。opacity/translate 在 build() 里直接读它才会重画。
  @State appeared: boolean = false;
  private appearTimer: number = -1;

  aboutToAppear(): void {
    if (this.appearDelay > 0) {
      this.appearTimer = setTimeout(() => {
        this.appearTimer = -1;
        this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
          this.appeared = true;
        });
      }, this.appearDelay);
    } else {
      this.appeared = true;
    }
  }

  aboutToDisappear(): void {
    if (this.appearTimer !== -1) {
      clearTimeout(this.appearTimer);
      this.appearTimer = -1;
    }
  }

  @Builder none() {}

  @Builder arrowBtn(icon: string, cb: () => void) {
    Row() {
      // v4.23：arrow_left/right 在 fs16 墨迹最短边 12.0vp，满足 2.1.4.3.2
      SymbolGlyph(sym(icon)).fontSize(S.iconSize).fontColor([tk(this.pal, 'textSub')])
    }
    .width(22)
    .height(22)
    .borderRadius(S.radiusSm)
    .backgroundColor(tk(this.pal, 'card'))
    .border({ width: 1, color: tk(this.pal, 'line') })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { cb(); })
    // v5.0：按压回弹
    .stateStyles({ pressed: { .scale({ x: 0.88, y: 0.88 }) } })
    .animation({ duration: 120, curve: Curve.EaseOut })
  }

  private numOf(v: Length): number {
    if (typeof v === 'number') {
      return v;
    }
    if (typeof v === 'string') {
      const n: number = parseFloat(v);
      return isNaN(n) ? 0 : n;
    }
    return 0;
  }

  // 卡片内容（头部 + 身体）。抽成 @Builder 是为了外层能统一挂高度上报。
  @Builder
  cardInner() {
    if (this.title.length > 0) {
      Row({  space: S.spaceMd  }) {
        Text(this.title)
          .fontSize(S.cardTitleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(tk(this.pal, 'text'))
        if (this.sub.length > 0) {
          Text(this.sub).fontSize(S.tinySize).fontColor(tk(this.pal, 'textFaint'))
        }
        Blank()
        if (this.headMode === 'arrows') {
          Row({  space: S.spaceSm  }) {
            this.arrowBtn('left', this.onPrev)
            this.arrowBtn('right', this.onNext)
          }
        } else if (this.headMode === 'link' || this.headMode === 'add') {
          Row({  space: S.spaceSm  }) {
            Text(this.headText)
              .fontSize(S.subSize)
              .fontColor(this.headMode === 'add' ? onFill(this.pal) : tk(this.pal, 'textSub'))
            if (this.headMode === 'link') {
              // v4.23：fs14 墨迹 11.7x10.6vp（盒子 14x14 >= 12vp、墨迹 >= 8vp）
              SymbolGlyph(sym('right')).fontSize(S.cardTitleSize).fontColor([tk(this.pal, 'textHint')])
            }
          }
          .padding({  left: this.headMode === 'add' ? 10 : 9, right: this.headMode === 'add' ? 10 : 9, top: S.spaceSm, bottom: S.spaceSm  })
          .borderRadius(this.headMode === 'add' ? 9 : 999)
          .backgroundColor(this.headMode === 'add' ? tk(this.pal, 'brand') : tk(this.pal, 'card'))
          .border(this.headMode === 'add'
            ? { width: 0, color: tk(this.pal, 'card') }
            : { width: 1, color: tk(this.pal, 'line') })
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.onHead(); })
        } else if (this.headMode === 'text') {
          Text(this.headText)
            .fontSize(S.subSize)
            .fontColor(tkInk(this.pal, 'brandDeep'))
            .onClick(() => { this.onHead(); })
        }
      }
      .width('100%')
      .padding({  left: S.headPadH, right: S.headPadH, top: S.headPadT  })
      .alignItems(VerticalAlign.Center)
    }
    Column() {
      this.content()
    }
    .width('100%')
    .padding({  left: S.bodyPadH, right: S.bodyPadH, top: this.bodyPadTop, bottom: this.bodyPadBottom  })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Column() {
        this.cardInner()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onAreaChange((oldA: Area, newA: Area) => {
        this.onContentHeight(this.numOf(newA.height));
      })
    }
    .width('100%')
    .height(this.fixedHeight > 0 ? this.fixedHeight : 'auto')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(tk(this.pal, 'card'))
    .borderRadius(S.radiusCard)
    .border({ width: 1, color: tk(this.pal, 'cardBorder') })
    .shadow(cardShadow(this.pal))
    // v5.0：入场淡入 + 轻微上浮（appearDelay > 0 时才有延迟浮现）
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : 10 })
  }
}
