/*
 * EdgeHint · 边界提示胶囊（v4.24 新增）
 *
 * 挂在 pages/Index.ets 根 Stack 的最后一层（最上面），用 AppStorage 接收
 * utils/EdgeHint.ets 发出的信号：
 *   - 内容被拉出边界时，在靠近那条边的位置弹一个小胶囊（「已经到顶了 / 已经到底了」）
 *   - 淡入淡出；不拦截任何触摸（HitTestMode.None 写在**使用处**）
 *
 * 为什么放在 Index 而不是每个页面里：
 *   17 处 Scroll 分布在 13 个文件里，每个页面自己画一套胶囊要改 13 遍；
 *   根 Stack 是所有主页面共用的父级，一个实例就够。
 *   （bindSheet 抽屉里的 Scroll 在独立弹层，根 Stack 盖不到它 —— 那里靠回弹本身给反馈。）
 *
 * v4.24 踩过的坑（别再改回去）：
 *   1) 淡入淡出用 .transition(TransitionEffect.OPACITY...) 会在节点反复重建时停在 opacity 0，
 *      胶囊永远看不见；改成 animateTo 手动改 .opacity() 才稳。
 *   2) .hitTestBehavior(HitTestMode.None) 必须写在**使用处**（EdgeHint({}) 这一行），
 *      写在组件内部只作用到它自己的根节点，结果整屏触摸被吞掉、整个 App 点不动。
 */

import { EDGE_BOTTOM, EDGE_END, EDGE_SEQ_KEY, EDGE_SIDE_KEY, EDGE_START, EDGE_TEXT_KEY } from '../utils/EdgeHint';

@Component
export struct EdgeHint {
  /** 深色模式 */
  @StorageLink('wb_dark') dark: boolean = false;
  /** 提示文字 */
  @StorageLink(EDGE_TEXT_KEY) @Watch('onHit') text: string = '';
  /** 触发的边（0 上 / 1 下 / 2 左 / 3 右） */
  @StorageLink(EDGE_SIDE_KEY) side: number = 0;
  /** 触发序号：每次触发都会变，用来监听 */
  @StorageLink(EDGE_SEQ_KEY) @Watch('onHit') seq: number = 0;
  /** 胶囊是否在树里 */
  @State showPill: boolean = false;
  /** 胶囊不透明度（用 animateTo 手动做淡入淡出） */
  @State pillOpacity: number = 0;
  private timer: number = -1;

  private onHit(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    // 先把旧的收掉，再弹新的
    this.showPill = true;
    this.pillOpacity = 0;
    this.getUIContext().animateTo({ duration: 160 }, () => {
      this.pillOpacity = 1;
    });
    this.timer = setTimeout(() => {
      this.getUIContext().animateTo({ duration: 220 }, () => {
        this.pillOpacity = 0;
      });
      this.timer = setTimeout(() => {
        this.showPill = false;
        this.timer = -1;
      }, 240);
    }, 1600);
  }

  /** 胶囊贴在哪条边 */
  private alignOf(side: number): Alignment {
    if (side === EDGE_BOTTOM) {
      return Alignment.Bottom;
    }
    if (side === EDGE_START) {
      return Alignment.Start;
    }
    if (side === EDGE_END) {
      return Alignment.End;
    }
    return Alignment.Top;
  }

  /** 离那条边留多远（底部要避开导航栏） */
  private marginOf(side: number): Margin {
    if (side === EDGE_BOTTOM) {
      return { top: 0, bottom: 108, left: 0, right: 0 };
    }
    if (side === EDGE_START) {
      return { top: 0, bottom: 0, left: 20, right: 0 };
    }
    if (side === EDGE_END) {
      return { top: 0, bottom: 0, left: 0, right: 20 };
    }
    return { top: 74, bottom: 0, left: 0, right: 0 };
  }

  build() {
    Stack({ alignContent: this.alignOf(this.side) }) {
      if (this.showPill) {
        Text(this.text)
          .fontSize(12)
          .fontColor(this.dark ? '#16202C' : '#FFFFFF')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(999)
          .backgroundColor(this.dark ? 'rgba(232,239,247,0.95)' : 'rgba(23,52,80,0.90)')
          .margin(this.marginOf(this.side))
          .opacity(this.pillOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
