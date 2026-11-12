/*
 * SheetFrame · 弹层外壳（v4.6 新增）
 *
 * 为什么要它：
 *   手机上任务 / 日程 / 项目这些表单用的是 bindSheet（底部抽屉）——单手够得着，是手机的原生手势。
 *   但平板 / 折叠屏展开后，底部抽屉会横跨 1000+ vp，像一张横幅铺在屏幕底部，很丑；
 *   而「记录灵感」的新建编辑器从 v4.4 起就是「居中卡片 + 遮罩」，在平板上好看得多。
 *   所以宽屏时改成和记录灵感一样的居中弹窗，手机保持原来的底部抽屉。
 *
 * 做法：
 *   1) bindSheet 的选项跟着宽窄变：
 *        宽屏 → height '100%' + backgroundColor Color.Transparent + dragBar false
 *        窄屏 → SheetSize.FIT_CONTENT + tk(this.dark, 'card') + dragBar true
 *   2) 弹层内容交给本组件：宽屏时渲染「遮罩 + 居中卡片」，窄屏时原样透传。
 *
 * 遮罩色、圆角、阴影都和记录灵感的编辑器保持一致（rgba(23,52,80,0.42) / 22 / radius 30）。
 */
import { C, tk, tc } from '../utils/Theme';
import { R } from '../utils/Responsive';

@Component
export struct SheetFrame {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  /** 宽屏？宽屏走「遮罩 + 居中卡片」，窄屏原样透传 */
  @Prop wide: boolean = false;
  /** 点遮罩时关闭（一般就是「把这个弹层关掉」） */
  onClose: () => void = () => {};
  /** 弹层本体（由调用方用 `content: () => { this.xxx(); }` 传进来） */
  @BuilderParam content: () => void = this.emptyContent;


  /** @BuilderParam 的默认值必须是一个 @Builder 方法（编译器要求） */
  @Builder
  emptyContent() {
  }

  build() {
    if (this.wide) {
      Stack({ alignContent: Alignment.Center }) {
        // 遮罩：点一下关掉弹层（v4.26 宽屏走页面内浮层，遮罩由这里画）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(23,52,80,0.42)')
          .onClick(() => { this.onClose(); })

        // 卡片：居中、限宽、限高
        //
        // v4.26（平板竖屏）：宽屏时各页的 bindSheet 改用系统的「居中弹窗」形态
        //   （SheetOptions.preferType = SheetType.POPUP）——遮罩由系统画、铺满整屏。
        //   之前这里自己画遮罩，试过三种面板高度（'100%' / R.windowH() 数值 / SheetSize.LARGE），
        //   实测 bindSheet 的面板高度是平台按「内容高度」算的（平板竖屏只有 560vp），
        //   自己画的遮罩最多只能盖住面板那一块 ⇒ 屏幕上半部分不暗、卡片底部按钮被裁掉。
        //   改用 POPUP 后，遮罩是系统的、整屏都暗，卡片自己居中。
        //
        // v4.25：这里原来还套了一层 Scroll，结果把内容自己的 Scroll 的手势吃掉了 ——
        //   外层 Scroll 先拿到拖动，而它的内容（表单那张卡）比它自己的 maxHeight 矮，
        //   外层滚不动 ⇒ 手指在表单上怎么拖都没反应；反过来，窗口比屏幕矮的时候
        //   （平板横屏 / 分屏 / 悬浮窗），外层需要滚却滚不动 ⇒ 底下的「保存」永远够不着。
        //   ⇒ 直接渲染内容，不套第二层 Scroll；高度由内容自己的 Scroll 负责，
        //   整张卡片再用 sheetMaxH() 卡住，保证「头部 + 表单 + 按钮条」都在窗口里。
        Column() {
          this.content()
        }
        .width('92%')
        .constraintSize({ maxWidth: 520, maxHeight: R.sheetMaxH() })
        .backgroundColor(tk(this.dark, 'card'))
        .borderRadius(22)
        .clip(true)
        .shadow({ radius: 30, color: 'rgba(23,52,80,0.26)', offsetX: 0, offsetY: 14 })
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
    } else {
      // 窄屏：底部抽屉。
      // 面板背景已改成透明（见各页 bindSheet 的 backgroundColor），
      // 所以系统的拖拽条 dragBar 画不出来（它跟着面板背景色走），
      // 这里自己画一个同样的小把手；白色圆角底也由这一层负责。
      Column() {
        Column()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor(tc(this.dark, '#C9D8E6', 0))
          .margin({ top: 8 })
        this.content()
      }
      .width('100%')
      .backgroundColor(tk(this.dark, 'card'))
      .borderRadius(22)
      .clip(true)
    }
  }
}
