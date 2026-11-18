// 一批「小方块」组件，全部照抄工作台 CSS 里的对应规则。
// 放在一个文件里是为了少建几个文件，每个 struct 都是独立的。
import { brandGradient, catBg, catColor, miniGradient, misc, onFill, paletteList, S, tc, tk, tkInk, trackGradient } from '../utils/Theme';
import { sym } from './Icon';
import { IconBox } from './IconBox';
// v5.0：数字滚动（首页 KPI）
import { AnimatedNum } from './AnimatedNum';

/** .kpi —— 白底圆角 18（手机端 15）、padding 11/12、数字 22 bold */
@Component
export struct Kpi {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop label: string = '';
  @Prop icon: string = 'home';
  @Prop iconBg: string = '';
  @Prop iconFg: string = '';
  @Prop value: string = '0';
  @Prop unit: string = '';
  @Prop sub: string = '';
  @Prop subColor: string = '';
  /** 0–100，负数表示不画进度条 */
  @Prop pct: number = -1;
  // v5.0：≥0 时用 AnimatedNum 让数字「滚」到新值（-1 = 保持静态文本）
  @Prop numValue: number = -1;
  // v5.0：numValue 的小数位（0 = 整数）
  @Prop numDecimals: number = 0;

  build() {
    Column({  space: S.spaceXs  }) {
      Row({  space: S.spaceLg  }) {
        IconBox({ name: this.icon, boxSize: 27, iconSize: 14, radius: 9, bg: this.iconBg.length > 0 ? this.iconBg : catBg(this.pal, 'work'), fg: this.iconFg.length > 0 ? this.iconFg : tk(this.pal, 'work') })
        Text(this.label).fontSize(S.tinySize).fontColor(tc(this.pal, '#8095A8', 1))
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({  space: S.spaceXs  }) {
        // v5.0：数字滚动。numValue ≥ 0 时用 AnimatedNum；否则退回静态文本。
        if (this.numValue >= 0) {
          AnimatedNum({ value: this.numValue, decimals: this.numDecimals })
        } else {
          Text(this.value)
            .fontSize(S.numberSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(tk(this.pal, 'text'))
        }
        if (this.unit.length > 0) {
          Text(this.unit).fontSize(S.subSize).fontColor(tk(this.pal, 'textFaint')).margin({  bottom: S.spaceSm  })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      if (this.sub.length > 0) {
        Text(this.sub)
          .fontSize(S.microSize + 0.5)
          .fontColor(this.subColor.length > 0 ? this.subColor : misc(this.pal, 'subColor', '#52697E'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.pct >= 0) {
        Row() {
          Row()
            .height(4)
            .width(`${Math.max(0, Math.min(100, this.pct))}%`)
            .borderRadius(S.radiusPill)
            .linearGradient(trackGradient(this.pal))
        }
        .width('100%')
        .height(4)
        .borderRadius(S.radiusPill)
        .backgroundColor(tk(this.pal, 'track'))
        .margin({  top: S.spaceMd  })
      }
    }
    .width('100%')
    .padding({  left: S.space2Xl, right: S.space2Xl, top: S.space2Xl, bottom: S.space2Xl  })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(tk(this.pal, 'card'))
    .borderRadius(S.radiusCard)
    .border({ width: 1, color: tk(this.pal, 'cardBorder') })
  }
}

/** .mod —— 模块格：浅底 13 圆角，图标 29 + 两行字 */
@Component
export struct Chip {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop text: string = '';
  @Prop active: boolean = false;
  onTap: () => void = () => {};

  build() {
    // v5.15 可访问性：药丸本身还是原来那么高（约 22vp），外面套一层 40 高的透明热区，
    //   手指点得到的范围 ≥40 高，视觉密度不变。
    Row() {
      Text(this.text)
        .fontSize(S.subSize)
        .fontColor(this.active ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#6A7F92', 1))
        .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
        .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceMd, bottom: S.spaceMd  })
        .borderRadius(S.radiusPill)
        .backgroundColor(this.active ? tk(this.pal, 'brandSoft') : tk(this.pal, 'card'))
        .border({ width: 1, color: this.active ? tk(this.pal, 'brandLine') : tk(this.pal, 'line') })
    }
    .height(40)
    .constraintSize({ minWidth: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onTap(); })
    // v5.15：读屏软件念的是这个文字（和药丸上写的一样）
    .accessibilityText(this.text)
  }
}

/** .sec-head —— 区块标题 + 灰色件数 + 右侧控件 */
@Component
export struct SecHead {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop title: string = '';
  @Prop count: string = '';
  /** '' | 'arrows' | 'add' | 'text' */
  @Prop rightMode: string = '';
  @Prop rightText: string = '';
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onRight: () => void = () => {};

  // v5.15 可访问性：箭头小方块视觉还是 22×22，外面套 40×40 的透明热区。
  //   label 是给读屏软件念的。
  @Builder arrowBtn(icon: string, label: string, cb: () => void) {
    Row() {
      Row() {
        // v4.23：arrow_left/right 在 fs16 墨迹最短边 12.0vp，满足 2.1.4.3.2
        SymbolGlyph(sym(icon)).fontSize(S.iconSize).fontColor([tc(this.pal, '#7C8F9F', 1)])
      }
      .width(22)
      .height(22)
      .borderRadius(S.radiusSm)
      .backgroundColor(tk(this.pal, 'card'))
      .border({ width: 1, color: tk(this.pal, 'line') })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { cb(); })
    .accessibilityText(label)
  }

  build() {
    Row({  space: S.spaceLg  }) {
      Text(this.title).fontSize(S.midSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text'))
      if (this.count.length > 0) {
        Text(this.count).fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint'))
      }
      Blank()
      if (this.rightMode === 'arrows') {
        Row({  space: S.spaceMd  }) {
          this.arrowBtn('left', '上一个', this.onPrev)
          this.arrowBtn('right', '下一个', this.onNext)
        }
      } else if (this.rightMode === 'add') {
        // v5.15 可访问性：外面套 40 高的透明热区，按钮本身的样子不变
        Row() {
          Row({  space: S.spaceSm  }) {
            SymbolGlyph(sym('plus')).fontSize(S.cardTitleSize).fontColor([onFill(this.pal)])
            Text(this.rightText).fontSize(S.subSize).fontColor(onFill(this.pal))
          }
          .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
          .borderRadius(S.radiusSm)
          .backgroundColor(tk(this.pal, 'brand'))
          .alignItems(VerticalAlign.Center)
        }
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.onRight(); })
        .accessibilityText(this.rightText)
      } else if (this.rightMode === 'text') {
        // v5.15 可访问性：文字按钮也补上 40 高的热区
        Row() {
          Text(this.rightText)
            .fontSize(S.subSize)
            .fontColor(tkInk(this.pal, 'brandDeep'))
        }
        .height(40)
        .constraintSize({ minWidth: 40 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.onRight(); })
        .accessibilityText(this.rightText)
      }
    }
    .width('100%')
    .margin({  top: S.space5Xl, bottom: S.spaceXl  })
    .padding({  left: S.spaceXs, right: S.spaceXs  })
    .alignItems(VerticalAlign.Center)
  }
}

/** 日历格子（.mc-day）
 *  v2.9：加 done/total —— 每天完成了几项，当天一共安排了几项。
 */
export interface GanttBar {
  label: string;
  startIdx: number;
  endIdx: number;
  bg: string;
  fg: string;
  dayLabel: string;
}

export function ganttBar(label: string, startIdx: number, endIdx: number, bg: string, fg: string, dayLabel: string): GanttBar {
  return { label: label, startIdx: startIdx, endIdx: endIdx, bg: bg, fg: fg, dayLabel: dayLabel };
}

/** .w-days + lanes —— 7 天时间块
 *  v2.9：日期可以点（onDayTap），选中的那天高亮（selectedIdx）。
 */
@Component
export struct WeekGantt {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop dayNums: string[] = [];
  @Prop todayIdx: number = -1;
  @Prop bars: GanttBar[] = [];
  @Prop selectedIdx: number = -1;
  onDayTap: (idx: number) => void = () => {};

  build() {
    Column({  space: 0  }) {
      Row() {
        ForEach(this.dayNums, (d: string, i: number) => {
          Column({  space: S.spaceXs  }) {
            Text(['一', '二', '三', '四', '五', '六', '日'][i]).fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint'))
            Row() {
              Text(d)
                .fontSize(S.subSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(i === this.todayIdx ? onFill(this.pal) : (i === this.selectedIdx ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#5E7183', 1)))
            }
            .width(23)
            .height(23)
            .borderRadius(S.radiusInner)
            .justifyContent(FlexAlign.Center)
            .border(i === this.selectedIdx && i !== this.todayIdx
              ? { width: 1.5, color: tk(this.pal, 'brand') }
              : { width: 0, color: Color.Transparent })
            .linearGradient(i === this.todayIdx
              ? brandGradient(this.pal)
              : { angle: 90, colors: [['#00000000', 0], ['#00000000', 1]] })
          }
          .layoutWeight(1)
          // v5.15 可访问性：日期格的可点区域补到 ≥40 高
          .constraintSize({ minHeight: 40 })
          .justifyContent(FlexAlign.Center)
          .onClick(() => { this.onDayTap(i); })
          // v5.15：读屏软件念「选择17号」
          .accessibilityText(`选择${d}号`)
        }, (d: string, i: number) => `wd${i}-${d}-${this.selectedIdx}-${this.pal}`)
      }
      .width('100%')

      // v5.4：没有横条时整块不画 —— 以前固定占 34px，空在那儿像多了一截空白。
      if (this.bars.length > 0) {
        Stack() {
          ForEach(this.bars, (b: GanttBar, i: number) => {
            Row() {
              Text(b.label)
                .fontSize(S.tinySize)
                .fontColor(b.fg)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(20)
            .padding({  left: S.spaceXl, right: S.spaceXl  })
            .borderRadius(S.radiusSm)
            .backgroundColor(b.bg)
            .width(`${(b.endIdx - b.startIdx + 1) * 100 / 7}%`)
            .position({ x: `${b.startIdx * 100 / 7}%`, y: i * 34 + 7 })
          }, (b: GanttBar, i: number) => `gb${i}-${b.label}-${this.pal}`)
        }
        .width('100%')
        .height(Math.max(34, this.bars.length * 34 + 6))
        .alignContent(Alignment.TopStart)
      }
    }
    .width('100%')
  }
}
