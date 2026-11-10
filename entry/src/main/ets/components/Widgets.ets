// 一批「小方块」组件，全部照抄工作台 CSS 里的对应规则。
// 放在一个文件里是为了少建几个文件，每个 struct 都是独立的。
import { brandGradient, C, catBg, catColor, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from './Icon';
import { IconBox } from './IconBox';

/** .kpi —— 白底圆角 18（手机端 15）、padding 11/12、数字 22 bold */
@Component
export struct Kpi {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop label: string = '';
  @Prop icon: string = 'home';
  @Prop iconBg: string = '#E8F2FC';
  @Prop iconFg: string = '#2F7FC4';
  @Prop value: string = '0';
  @Prop unit: string = '';
  @Prop sub: string = '';
  @Prop subColor: string = '#52697E';
  /** 0–100，负数表示不画进度条 */
  @Prop pct: number = -1;

  build() {
    Column({ space: 2 }) {
      Row({ space: 7 }) {
        IconBox({ name: this.icon, boxSize: 27, iconSize: 14, radius: 9, bg: this.iconBg, fg: this.iconFg })
        Text(this.label).fontSize(S.tinySize).fontColor(tc(this.dark, '#8095A8', 1))
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 2 }) {
        Text(this.value)
          .fontSize(S.numberSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(tk(this.dark, 'text'))
        if (this.unit.length > 0) {
          Text(this.unit).fontSize(10).fontColor(tk(this.dark, 'textFaint')).margin({ bottom: 3 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      if (this.sub.length > 0) {
        Text(this.sub)
          .fontSize(S.microSize + 0.5)
          .fontColor(this.subColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.pct >= 0) {
        Row() {
          Row()
            .height(4)
            .width(`${Math.max(0, Math.min(100, this.pct))}%`)
            .borderRadius(99)
            .linearGradient({ angle: 90, colors: [['#12706B', 0], ['#0F6B66', 1]] })
        }
        .width('100%')
        .height(4)
        .borderRadius(99)
        .backgroundColor(tk(this.dark, 'track'))
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(tk(this.dark, 'card'))
    .borderRadius(15)
    .border({ width: 1, color: tk(this.dark, 'cardBorder') })
  }
}

/** .mod —— 模块格：浅底 13 圆角，图标 29 + 两行字 */
@Component
export struct ModTile {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop icon: string = 'home';
  @Prop label: string = '';
  @Prop sub: string = '';
  @Prop iconBg: string = '#E8F2FC';
  @Prop iconFg: string = '#2F7FC4';
  onTap: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      IconBox({ name: this.icon, boxSize: 29, iconSize: 14, radius: 9, bg: this.iconBg, fg: this.iconFg })
      Column({ space: 1 }) {
        Text(this.label)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(tk(this.dark, 'text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.sub)
          .fontSize(8)
          .fontColor(tk(this.dark, 'textHint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 8, right: 6, top: 9, bottom: 9 })
    .borderRadius(S.radiusInner)
    .backgroundColor(tk(this.dark, 'card2'))
    .onClick(() => { this.onTap(); })
  }
}

/** .chip —— 筛选胶囊（10.5px，选中 acc-soft + acc-line + acc-d） */
@Component
export struct Chip {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop text: string = '';
  @Prop active: boolean = false;
  onTap: () => void = () => {};

  build() {
    Text(this.text)
      .fontSize(S.subSize)
      .fontColor(this.active ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#6A7F92', 1))
      .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(S.radiusPill)
      .backgroundColor(this.active ? tk(this.dark, 'brandSoft') : tk(this.dark, 'card'))
      .border({ width: 1, color: this.active ? tk(this.dark, 'brandLine') : tk(this.dark, 'line') })
      .onClick(() => { this.onTap(); })
  }
}

/** .sec-head —— 区块标题 + 灰色件数 + 右侧控件 */
@Component
export struct SecHead {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop title: string = '';
  @Prop count: string = '';
  /** '' | 'arrows' | 'add' | 'text' */
  @Prop rightMode: string = '';
  @Prop rightText: string = '';
  onPrev: () => void = () => {};
  onNext: () => void = () => {};
  onRight: () => void = () => {};

  @Builder arrowBtn(icon: string, cb: () => void) {
    Row() {
      // v4.23：arrow_left/right 在 fs16 墨迹最短边 12.0vp，满足 2.1.4.3.2
      SymbolGlyph(sym(icon)).fontSize(16).fontColor([tc(this.dark, '#7C8F9F', 1)])
    }
    .width(22)
    .height(22)
    .borderRadius(7)
    .backgroundColor(tk(this.dark, 'card'))
    .border({ width: 1, color: tk(this.dark, 'line') })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { cb(); })
  }

  build() {
    Row({ space: 8 }) {
      Text(this.title).fontSize(13.5).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text'))
      if (this.count.length > 0) {
        Text(this.count).fontSize(9).fontColor(tk(this.dark, 'textHint'))
      }
      Blank()
      if (this.rightMode === 'arrows') {
        Row({ space: 6 }) {
          this.arrowBtn('left', this.onPrev)
          this.arrowBtn('right', this.onNext)
        }
      } else if (this.rightMode === 'add') {
        Row({ space: 3 }) {
          SymbolGlyph(sym('plus')).fontSize(14).fontColor([onFill(this.dark)])
          Text(this.rightText).fontSize(10).fontColor(onFill(this.dark))
        }
        .padding({ left: 9, right: 10, top: 4, bottom: 4 })
        .borderRadius(9)
        .backgroundColor(tk(this.dark, 'brand'))
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.onRight(); })
      } else if (this.rightMode === 'text') {
        Text(this.rightText)
          .fontSize(10)
          .fontColor(tkInk(this.dark, 'brandDeep'))
          .onClick(() => { this.onRight(); })
      }
    }
    .width('100%')
    .margin({ top: 18, bottom: 9 })
    .padding({ left: 2, right: 2 })
    .alignItems(VerticalAlign.Center)
  }
}

/** 日历格子（.mc-day）
 *  v2.9：加 done/total —— 每天完成了几项，当天一共安排了几项。
 */
export interface CalCell {
  n: number;
  out: boolean;
  has: boolean;
  today: boolean;
  done: number;
  total: number;
}

export function calCell(n: number, out: boolean, has: boolean, today: boolean, done: number, total: number): CalCell {
  return { n: n, out: out, has: has, today: today, done: done, total: total };
}

/** 完成数热力色：完成越多颜色越深（和热力图一个思路） */
// v4.22：这一格要印白色完成数，色阶必须能被白字压住 >= 4.6:1。
// 原来最浅的 #BFE3F3 白字只有 1.36，整条色阶换成深蓝五档（最浅一档压白字 5.12）。
export function heatColor(n: number): string {
  if (n <= 0) { return '#BFE3F3'; }
  if (n === 1) { return '#3F7396'; }
  if (n === 2) { return '#356A8C'; }
  if (n === 3) { return '#2A5F80'; }
  if (n === 4) { return '#1B5170'; }
  return '#0B3E63';
}

/** .mc-grid —— 7 列月历 */
@Component
export struct MonthCal {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop cells: CalCell[] = [];
  @Prop monthLabel: string = '';
  @Prop doneCount: number = 0;

  build() {
    Column({ space: 3 }) {
      Row({ space: 4 }) {
        Text(this.monthLabel).fontSize(S.subSize).fontWeight(FontWeight.Medium).fontColor(tk(this.dark, 'text'))
        Blank()
        Text(`完成 ${this.doneCount} 项`).fontSize(S.microSize + 0.5).fontColor(tk(this.dark, 'textHint'))
      }
      .width('100%')
      .padding({ bottom: 5 })

      Row() {
        ForEach(['一', '二', '三', '四', '五', '六', '日'], (w: string) => {
          Row() {
            Text(w).fontSize(8.5).fontColor(tk(this.dark, 'textHint'))
          }.layoutWeight(1).justifyContent(FlexAlign.Center).padding({ bottom: 3 })
        }, (w: string) => w)
      }
      .width('100%')

      ForEach(this.rows(), (row: CalCell[], ri: number) => {
        Row({ space: 3 }) {
          ForEach(row, (c: CalCell, ci: number) => {
            Column({ space: 1 }) {
              // v4.4：补白格（n=0）以前会印出一个「0」，看着像日期
              Text(c.n > 0 ? `${c.n}` : '')
                .fontSize(S.subSize - 0.5)
                .fontWeight(c.today || c.has ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(c.today ? onFill(this.dark) : (c.out ? tc(this.dark, '#CFDCE7', 1) : (c.done > 0 ? tc(this.dark, '#1F5E7A', 1) : (c.has ? tc(this.dark, '#2F6C8A', 1) : tc(this.dark, '#54697C', 1)))))
              // v4.21：原来 7.5vp，低于华为 UX 2.1.4.2 的 8vp 下限；徽标跟着放大到 15
              Text(c.done > 0 ? `${c.done}` : '')
                .fontSize(9)
                .fontColor(onFill(this.dark))
                .textAlign(TextAlign.Center)
                .width(15)
                .height(15)
                .borderRadius(8)
                .backgroundColor(c.done > 0 ? heatColor(c.done) : Color.Transparent)
            }
            .layoutWeight(1)
            .height(32)
            .borderRadius(9)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(c.today ? Color.Transparent : (c.done > 0 ? tc(this.dark, '#EAF4FC', 0) : (c.has ? tc(this.dark, '#F6FAFD', 0) : Color.Transparent)))
            .linearGradient(c.today ? brandGradient() : { angle: 90, colors: [[this.dark ? '#1C2836' : '#FFFFFF', 0], [this.dark ? '#1C2836' : '#FFFFFF', 1]] })
          }, (c: CalCell, ci: number) => `${ri}-${ci}-${c.n}-${c.done}`)
        }
        .width('100%')
      }, (row: CalCell[], ri: number) => `r${ri}-${row.length}-${row[0] ? row[0].n : 0}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private rows(): CalCell[][] {
    const out: CalCell[][] = [];
    let cur: CalCell[] = [];
    for (let i = 0; i < this.cells.length; i++) {
      cur.push(this.cells[i]);
      if (cur.length === 7) { out.push(cur); cur = []; }
    }
    if (cur.length > 0) { out.push(cur); }
    return out;
  }
}

/** 迷你柱状图（.summary .mini-bars） */
@Component
export struct MiniBars {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop values: number[] = [];
  @Prop chartHeight: number = 44;

  build() {
    Row({ space: 4 }) {
      ForEach(this.values, (v: number, i: number) => {
        Column()
          .layoutWeight(1)
          .height(`${this.hOf(v)}%`)
          .borderRadius({ topLeft: 4, topRight: 4, bottomLeft: 2, bottomRight: 2 })
          .linearGradient({ angle: 180, colors: [[this.dark ? '#1E4E5E' : '#BFEAF8', 0], [this.dark ? '#17323E' : '#E4F4FC', 1]] })
      }, (v: number, i: number) => `mb${i}-${v}`)
    }
    .width('100%')
    .height(this.chartHeight)
    .alignItems(VerticalAlign.Bottom)
  }

  private hOf(v: number): number {
    let max = 1;
    for (let i = 0; i < this.values.length; i++) {
      if (this.values[i] > max) { max = this.values[i]; }
    }
    return Math.max(8, Math.round(v / max * 100));
  }
}

/** 甘特条（.w-row .bar） */
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
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop dayNums: string[] = [];
  @Prop todayIdx: number = -1;
  @Prop bars: GanttBar[] = [];
  @Prop selectedIdx: number = -1;
  onDayTap: (idx: number) => void = () => {};

  build() {
    Column({ space: 0 }) {
      Row() {
        ForEach(this.dayNums, (d: string, i: number) => {
          Column({ space: 1 }) {
            Text(['一', '二', '三', '四', '五', '六', '日'][i]).fontSize(9).fontColor(tk(this.dark, 'textHint'))
            Row() {
              Text(d)
                .fontSize(S.subSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(i === this.todayIdx ? onFill(this.dark) : (i === this.selectedIdx ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#5E7183', 1)))
            }
            .width(23)
            .height(23)
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)
            .border(i === this.selectedIdx && i !== this.todayIdx
              ? { width: 1.5, color: tk(this.dark, 'brand') }
              : { width: 0, color: Color.Transparent })
            .linearGradient(i === this.todayIdx
              ? brandGradient()
              : { angle: 90, colors: [['#00000000', 0], ['#00000000', 1]] })
          }
          .layoutWeight(1)
          .onClick(() => { this.onDayTap(i); })
        }, (d: string, i: number) => `wd${i}-${d}-${this.selectedIdx}`)
      }
      .width('100%')

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
          .padding({ left: 9, right: 9 })
          .borderRadius(7)
          .backgroundColor(b.bg)
          .width(`${(b.endIdx - b.startIdx + 1) * 100 / 7}%`)
          .position({ x: `${b.startIdx * 100 / 7}%`, y: i * 34 + 7 })
        }, (b: GanttBar, i: number) => `gb${i}-${b.label}`)
      }
      .width('100%')
      .height(Math.max(34, this.bars.length * 34 + 6))
      .alignContent(Alignment.TopStart)
    }
    .width('100%')
  }
}
