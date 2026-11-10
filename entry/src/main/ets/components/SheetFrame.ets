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
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

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
        // 遮罩：点一下关掉弹层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(23,52,80,0.42)')
          .onClick(() => { this.onClose(); })

        // 卡片：居中、限宽、限高
        Column() {
          Scroll() {
            Column() {
              this.content()
            }
            .width('100%')
          }
          .onScrollEdge(onEdgeScrolled)
          .onWillScroll(onEdgeWillScroll)
          .edgeEffect(EdgeEffect.Spring)
          .width('100%')
          .constraintSize({ maxHeight: '82%' })
          .scrollBar(BarState.Off)
        }
        .width('92%')
        .constraintSize({ maxWidth: 520 })
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
