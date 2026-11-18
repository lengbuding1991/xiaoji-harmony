/*
 * SetRow · 设置页的一行（v5.20 新增）
 *
 * 为什么单独抽出来：
 *   设置页重做成「组标题 + 一张卡 + 每行一个功能」之后，同一种行要在好几个地方
 *   出现（本地数据 / 备份与恢复 / 怎么称呼我 / 外观 / 提醒清单 / 隐私与协议 / 关于 / 清空）。
 *   行里要放「图标块 + 标题 + 说明 + 右侧内容 + 箭头」，
 *   如果写成 @Builder 参数传回调，会碰到 ArkUI V1 的老问题（函数型成员变量不能加 @Prop）。
 *
 *   ⚠️ 为什么不用「尾随闭包」放右侧内容：ArkTS 不允许在组件的尾随闭包里写 this
 *      （报 arkts-no-standalone-this），而右侧内容（当前配色名、版本号）恰恰要读父组件的状态。
 *      所以右侧内容改成 @Prop 传进来，父组件在 build 里算好。
 *
 * 右侧内容三种（trailingKind）：
 *   0 = 没有
 *   1 = 当前配色名（组件自己按 wb_pal 算 ⇒ 换配色立刻跟着变）
 *   2 = 一段自定义文字（trailingText）
 */
import { S, tk, tkInk } from '../utils/Theme';
import { PALETTES } from '../utils/Palette';
import { sym } from './Icon';

@Component
export struct SetRow {
  // v5.8：配色索引（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  /** 左侧图标名（见 components/Icon.ets 的 sym 名单） */
  @Prop icon: string = 'doc';
  /** 行标题 */
  @Prop title: string = '';
  /** 行说明（可空） */
  @Prop sub: string = '';
  /** 右边要不要小箭头（能点开的才有） */
  @Prop arrow: boolean = false;
  /** 右侧内容：0=无 1=当前配色名 2=自定义文字 */
  @Prop trailingKind: number = 0;
  /** trailingKind=2 时显示的文字 */
  @Prop trailingText: string = '';
  /** 右侧文字用危险色（红） */
  @Prop trailingDanger: boolean = false;
  /** 点击这一行（普通成员变量，不能加 @Prop：函数型变量不允许） */
  onTap: () => void = () => {};

  build() {
    Row({  space: S.space2Xl  }) {
      // 左侧图标块：32vp 圆角浅底 + 品牌色符号
      Column() {
        SymbolGlyph(sym(this.icon))
          .fontSize(S.iconSize)
          .fontColor([tkInk(this.pal, 'brandDeep')])
      }
      .width(32)
      .height(32)
      .borderRadius(S.radiusSm)
      .backgroundColor(tk(this.pal, 'soft'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .flexShrink(0)

      // 中间文字块
      Column({  space: S.spaceXs  }) {
        Text(this.title)
          .fontSize(S.cardTitleSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(tk(this.pal, 'text'))
        if (this.sub.length > 0) {
          Text(this.sub)
            .fontSize(S.labelSize)
            .fontColor(tk(this.pal, 'textSub'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧内容
      if (this.trailingKind === 1) {
        Text(this.paletteName())
          .fontSize(S.labelSize)
          .fontColor(tk(this.pal, 'textSub'))
          .flexShrink(0)
      } else if (this.trailingKind === 2) {
        Text(this.trailingText)
          .fontSize(this.trailingDanger ? S.labelSize : S.labelSize)
          .fontWeight(this.trailingDanger ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.trailingDanger ? tkInk(this.pal, 'danger') : tk(this.pal, 'textSub'))
          .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceMd, bottom: S.spaceMd  })
          .flexShrink(0)
      }

      if (this.arrow) {
        SymbolGlyph(sym('right'))
          .fontSize(S.iconSize)
          .fontColor([tk(this.pal, 'textPale')])
          .flexShrink(0)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: 56 })
    .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceXl, bottom: S.spaceXl  })
    .onClick(() => { this.onTap(); })
  }

  /** 当前配色名（索引越界退回第一套） */
  private paletteName(): string {
    const idx: number = this.pal >= 0 && this.pal < PALETTES.length ? this.pal : 0;
    return PALETTES[idx].name;
  }
}
