// 日历安排
// 逐块对齐「个人工作台」components/CalendarApp.tsx 的手机端：
//   eyebrow「CALENDAR · 日历安排」→ h1 周视图「这一周，先占住时间。」/ 日视图「这一天，先占住时间。」
//   → 右侧 周/日 两个 chip + ‹ 今天 ›
//   → 周视图：每天一卡（.mw-day / .mw-head / .mw-ev / .mw-empty）
//   → 日视图：时间轴 + 当天空闲整块（.ds-gap）+ 点空白新建
// 新建/编辑日程统一走 EventSheet。
import { Store } from '../store/Store';
import { advanceDate } from '../db/Repo';
import { areaColor, areaLabel, C, S, tc, tk, tkInk } from '../utils/Theme';
import { R } from '../utils/Responsive';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { Chip } from '../components/Widgets';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { EventSheet } from '../components/EventSheet';
import { EventItem, Task, TaskEventLink } from '../api/Types';
import { TopBar } from '../components/TopBar';
import { SheetFrame } from '../components/SheetFrame';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

const GAP_START: number = 7 * 60;   // 工作台 GAP_START = 7:00
const GAP_END: number = 23 * 60;   // 工作台 GAP_END   = 23:00
const MIN_GAP: number = 45;        // 小于 45 分钟的空档不算「整块」
// 日视图右侧「空着的整块时间」专用（对齐 CalendarApp 的 gaps：9:00–21:00、>=60 分钟）
const DAY_GAP_START: number = 9 * 60;
const DAY_GAP_END: number = 21 * 60;
const DAY_GAP_MIN: number = 60;

@Component
export struct CalendarView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tick: number = 0;
  // v4.6：宽屏档位（宽屏时弹层限宽）
  @StorageLink('wb_layout') layoutMode: number = 0;
  @State events: EventItem[] = [];
  // v4.5：周标题里的日期范围也是派生值 ⇒ 进 @State
  @State kWeekLabel: string = '';
  @State tasks: Task[] = [];
  /** 0 = 周视图，1 = 日视图（手机默认日视图，对齐 CalendarApp） */
  @State view: number = 1;
  /** 周视图的周偏移（0 = 本周） */
  @State weekOffset: number = 0;
  /** 日视图选中的日期 */
  @State selected: string = D.today();

  @State showSheet: boolean = false;
  // v4.26（平板竖屏）：宽屏的弹层不再用 bindSheet。
  //   bindSheet 的面板高度是平台按「内容高度」算的（平板竖屏实测只有 560vp），
  //   卡片会被裁掉底部「保存/取消」，自己画的遮罩也只能盖住面板那一块。
  //   ⇒ 宽屏改成在页面里自己铺一层遮罩 + 居中卡片（wideOverlay），窄屏仍是底部抽屉。
  @State wideOpen: boolean = false;

  /** v4.26：宽屏走页面内浮层，窄屏走 bindSheet 底部抽屉 */
  private openSheet(): void {
    if (this.wideMode()) {
      this.wideOpen = true;
      // 浮层盖住内容区时，右下角的悬浮按钮（在页面层）会浮到遮罩上面，先藏掉
      AppStorage.setOrCreate<boolean>('wb_fab_hide', true);
    } else {
      this.showSheet = true;
    }
  }

  private closeSheet(): void {
    this.showSheet = false;
    this.wideOpen = false;
    AppStorage.setOrCreate<boolean>('wb_fab_hide', false);
  }

  /** v4.26：宽屏时铺在页面最上层的遮罩 + 居中卡片 */
  @Builder
  wideOverlay() {
    if (this.wideMode() && this.wideOpen) {
      this.sheetContent()
    }
  }

  // v4.4：ArkUI V1 只刷新「表达式里直接读过 state」的节点，
  // 方法调用里的派生值（weekCount() / tasksOf().length / dayGaps()…）不算依赖，
  // 数据变了不会自己更新 ⇒ 全部预计算进 @State。
  @State kWeekCount: number = 0;
  @State kSelEvents: EventItem[] = [];
  @State kSelAllDay: EventItem[] = [];
  @State kSelTasks: Task[] = [];
  @State kSelGaps: number[][] = [];
  @State kSelOccupied: number = 0;
  /** v4.12：任务 ↔ 日程 关联（日历里合并成一条） */
  @State teLinks: TaskEventLink[] = [];
  onNavigate: (page: string) => void = () => {};
  @State editingId: number = -1;
  @State sheetDate: string = '';
  @State sheetStart: string = '';
  @State sheetEnd: string = '';

  private unsub: () => void = () => {};

  /** v4.6：宽屏？ */
  private wideMode(): boolean {
    return this.layoutMode >= 1;
  }

  private syncStore(): void {
    this.events = Store.I.events;
    this.tasks = Store.I.tasks;
    this.teLinks = Store.I.taskEventLinks;
    this.recalc();
  }

  /** 把选中那天 / 本周的派生值算好 */
  private recalc(): void {
    this.kWeekLabel = this.weekRangeLabel();
    const ws: string = this.weekRangeStartKey();
    const we: string = this.weekRangeEndKey();
    let n: number = 0;
    for (const e of this.events) {
      if (e.repeat_rule !== 'none') { n += 1; continue; }
      const d: string = D.dateOf(e.start_at);
      if (d >= ws && d <= we) { n += 1; }
    }
    this.kWeekCount = n;

    const timed: EventItem[] = [];
    const allDay: EventItem[] = [];
    for (const e of this.eventsOf(this.selected)) {
      if (e.all_day === 1) { allDay.push(e); } else { timed.push(e); }
    }
    this.kSelEvents = timed;
    this.kSelAllDay = allDay;
    // v4.12：跟日程关联上的任务不在下面重复列（日程那一行里已经带出来了）
    const keep: Task[] = [];
    for (const t of this.tasksOf(this.selected)) {
      if (!this.mergedIntoEvent(t.id, this.selected)) { keep.push(t); }
    }
    this.kSelTasks = keep;
    this.kSelGaps = this.gapsOf(this.selected);
    this.kSelOccupied = this.occupiedHours();
  }

  private weekRangeStartKey(): string {
    return D.key(this.weekStartDate());
  }

  private weekRangeEndKey(): string {
    return D.key(D.dateAdd(this.weekStartDate(), 6));
  }

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  // ── 周范围 ──
  private weekStartDate(): Date {
    return D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
  }

  private weekDays(): Date[] {
    const ws = this.weekStartDate();
    const out: Date[] = [];
    for (let i = 0; i < 7; i++) {
      out.push(D.dateAdd(ws, i));
    }
    return out;
  }

  private weekRangeLabel(): string {
    const ws = this.weekStartDate();
    const we = D.dateAdd(ws, 6);
    return `${D.md(D.key(ws))} – ${D.md(D.key(we))}`;
  }

  // ── 某天的数据 ──
  /**
   * 某天的日程（含重复日程的展开）。
   * v4.4：以前只按「原始开始日」匹配 —— 每周三的例会只在第一周出现，
   * 而提醒（Repo.reminders）和网页版都是按规则展开的 ⇒ 同一个 App 里两套口径。
   */
  private eventsOf(key: string): EventItem[] {
    const list: EventItem[] = [];
    for (const e of this.events) {
      if (e.repeat_rule === 'none') {
        if (D.dateOf(e.start_at) === key) { list.push(e); }
        continue;
      }
      // 重复日程：从第一次开始往后推，推过这一天就停
      let cur: Date = D.parse(e.start_at);
      // v4.5：拿「那天结束前」比，不能拿当天零点比 ——
      // 否则当天 09:00 的日程会因为 cur > 00:00 直接跳出循环，重复日程永远匹配不上。
      const target: Date = D.parse(`${key}T23:59`);
      let guard: number = 0;
      while (cur.getTime() <= target.getTime() && guard < 500) {
        if (D.key(cur) === key) { list.push(this.eventOn(e, cur)); }
        cur = advanceDate(cur, e.repeat_rule);
        guard += 1;
      }
    }
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        if (list[j].start_at < list[i].start_at) {
          const t = list[i];
          list[i] = list[j];
          list[j] = t;
        }
      }
    }
    return list;
  }

  /** 把重复日程挪到具体的那一天（时间点保持不变） */
  private eventOn(e: EventItem, day: Date): EventItem {
    const base: Date = D.parse(e.start_at);
    const d: Date = new Date(day.getTime());
    d.setHours(base.getHours(), base.getMinutes(), 0, 0);
    let endStr: string | null = null;
    if (e.end_at !== null && e.end_at.length > 0) {
      const eb: Date = D.parse(e.end_at);
      const durMin: number = Math.max(15, (eb.getTime() - base.getTime()) / 60000);
      const ed: Date = new Date(d.getTime() + durMin * 60000);
      endStr = `${D.key(ed)}T${this.hhmm(ed)}`;
    }
    const copy: EventItem = {
      id: e.id,
      title: e.title,
      start_at: `${D.key(d)}T${this.hhmm(d)}`,
      end_at: endStr,
      all_day: e.all_day,
      location: e.location,
      note: e.note,
      created_at: e.created_at,
      repeat_rule: e.repeat_rule,
      remind_min: e.remind_min
    };
    return copy;
  }

  private hhmm(d: Date): string {
    const h: number = d.getHours();
    const m: number = d.getMinutes();
    return `${h < 10 ? `0${h}` : `${h}`}:${m < 10 ? `0${m}` : `${m}`}`;
  }

  /**
   * 某天的任务。
   * v4.4：① 已完成的不要再占位置；② 排了具体时间的任务也要出现在日视图里
   * （以前只认到期日，任务面板里排了期的任务在日历上完全看不见）。
   */
  private tasksOf(key: string): Task[] {
    const list: Task[] = [];
    for (const t of this.tasks) {
      if (t.status === 'done') { continue; }
      if (t.due_date !== null && D.dateOf(t.due_date) === key) { list.push(t); continue; }
      if (t.scheduled_start !== null && D.dateOf(t.scheduled_start) === key) { list.push(t); }
    }
    return list;
  }

  /** v4.12：这个任务是不是已经被合并进某条日程了 */
  private mergedIntoEvent(taskId: number, key: string): boolean {
    for (const l of this.teLinks) {
      if (l.task_id !== taskId) { continue; }
      for (const e of this.events) {
        if (e.id === l.event_id && D.dateOf(e.start_at) === key) { return true; }
      }
    }
    return false;
  }

  /** v4.12：某条日程关联的任务标题 */
  private linkedTaskTitles(eventId: number): string {
    const names: string[] = [];
    for (const l of this.teLinks) {
      if (l.event_id !== eventId) { continue; }
      for (const t of this.tasks) {
        if (t.id === l.task_id) { names.push(t.title); break; }
      }
    }
    return names.join('、');
  }

  /** v4.12：任务是「已安排」（有安排时段）还是「到期」（只有截止日） */
  private taskKindTag(t: Task): string {
    if (t.scheduled_start !== null && D.dateOf(t.scheduled_start) === this.selected) { return '已安排'; }
    return '到期';
  }

  private minutesOf(s: string): number {
    const d = D.parse(s);
    return d.getHours() * 60 + d.getMinutes();
  }

  /** 当天的空闲整块（工作台 GAP_START..GAP_END 之间，扣掉日程，>=45 分钟） */
  private gapsOf(key: string): number[][] {
    const busy: number[][] = [];
    for (const e of this.eventsOf(key)) {
      const s: number = this.minutesOf(e.start_at);
      let en: number = s + 60;
      if (e.end_at !== null && e.end_at.length > 0) {
        // v4.4：跨天的日程，两个「当天第几分钟」相减会得到负数
        // （昨天 23:00 → 今天 01:00 会算出 -1320），以前被 max(15,…) 兜成 15 分钟，
        // 占用时间算错了。这里用真实的毫秒差。
        const diffMin: number = Math.round((D.parse(e.end_at).getTime() - D.parse(e.start_at).getTime()) / 60000);
        if (diffMin > 0) { en = s + diffMin; }
      }
      busy.push([s, en]);
    }
    // 按开始时间冒泡排序
    for (let i = 0; i < busy.length; i++) {
      for (let j = i + 1; j < busy.length; j++) {
        if (busy[j][0] < busy[i][0]) {
          const t = busy[i];
          busy[i] = busy[j];
          busy[j] = t;
        }
      }
    }
    const out: number[][] = [];
    let cur: number = GAP_START;
    for (const b of busy) {
      if (b[0] - cur >= MIN_GAP) {
        out.push([cur, Math.min(b[0], GAP_END)]);
      }
      if (b[1] > cur) { cur = b[1]; }
    }
    if (GAP_END - cur >= MIN_GAP) {
      out.push([cur, GAP_END]);
    }
    return out;
  }

  /**
   * 日视图「空着的整块时间」专用的空档计算（对齐 CalendarApp 的 gaps：9:00–21:00、>=60 分钟）。
   * 注意它与周视图的 gapsOf 不同：工作台日视图只统计有时间的日程，不看任务，起点也不是 7:00。
   */
  private dayGaps(): number[][] {
    const busy: number[][] = [];
    for (const e of this.eventsOf(this.selected)) {
      if (e.all_day === 1) { continue; }
      const st: number = this.minutesOf(e.start_at);
      const en: number = e.end_at !== null ? this.minutesOf(e.end_at) : st + 45;
      busy.push([st, en > st ? en : st + 45]);
    }
    for (let i = 0; i < busy.length; i++) {
      for (let j = i + 1; j < busy.length; j++) {
        if (busy[j][0] < busy[i][0]) {
          const t = busy[i];
          busy[i] = busy[j];
          busy[j] = t;
        }
      }
    }
    const out: number[][] = [];
    let cur: number = DAY_GAP_START;
    for (const b of busy) {
      if (b[0] - cur >= DAY_GAP_MIN) {
        out.push([cur, b[0]]);
      }
      if (b[1] > cur) { cur = b[1]; }
    }
    if (DAY_GAP_END - cur >= DAY_GAP_MIN) {
      out.push([cur, DAY_GAP_END]);
    }
    return out;
  }

  private hmOf(min: number): string {
    const h: number = Math.floor(min / 60);
    const m: number = min % 60;
    return `${h < 10 ? '0' : ''}${h}:${m < 10 ? '0' : ''}${m}`;
  }

  /** 已占时间（小时，对齐 .ds-foot 右格：全天/无结束按 45 分钟，否则取 max(15, 分钟差)） */
  private occupiedHours(): number {
    let mins: number = 0;
    const list: EventItem[] = this.eventsOf(this.selected);
    for (let i = 0; i < list.length; i++) {
      const e: EventItem = list[i];
      if (e.all_day === 1 || e.end_at === null) {
        mins += 45;
      } else {
        const a: number = this.minutesOf(e.start_at);
        const b: number = this.minutesOf(e.end_at);
        mins += Math.max(15, b - a);
      }
    }
    return Math.round(mins / 60);
  }

  private toneOf(e: EventItem): string {
    const n: number = e.id % 5;
    if (n === 0) { return tk(this.dark, 'event'); }
    if (n === 1) { return tk(this.dark, 'brand'); }
    if (n === 2) { return tk(this.dark, 'side'); }
    if (n === 3) { return tk(this.dark, 'media'); }
    return tk(this.dark, 'life');
  }

  // ── 打开弹窗 ──
  /** v4.4：新建日程的默认开始时间 = 当前时间向上取整到下一个整点
   *  （以前不管几点新建都是 09:00，很不贴合实际） */
  private nextHourMinutes(): number {
    const now: Date = new Date();
    const base: number = now.getHours() * 60 + now.getMinutes();
    const up: number = Math.ceil((base + 1) / 60) * 60;
    return up > 23 * 60 + 30 ? 9 * 60 : up;
  }

  private openNew(key: string, startMin: number): void {
    const useMin: number = startMin > 0 ? startMin : this.nextHourMinutes();
    const h: number = Math.floor(useMin / 60);
    const m: number = useMin % 60;
    const e0: number = useMin + 60;
    this.editingId = -1;
    this.sheetDate = key;
    this.sheetStart = this.hmOf(useMin);
    const endMin: number = e0 > 23 * 60 + 59 ? 23 * 60 + 59 : e0;
    this.sheetEnd = this.hmOf(endMin);
    this.openSheet();
  }

  private openEdit(id: number): void {
    this.sheetDate = '';
    this.sheetStart = '';
    this.sheetEnd = '';
    this.editingId = id;
    this.openSheet();
  }

  // ── 周视图：每天一卡 ──
  @Builder dayCard(d: Date) {
    Column() {
      Row({ space: 8 }) {
        Text(`周${D.weekdayOf(D.key(d))}`)
          .fontSize(11)
          .fontColor(tc(this.dark, '#8FA2B3', 1))
        Text(D.md(D.key(d)))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(tc(this.dark, '#33485A', 1))
        Blank()
        if (D.key(d) === D.today()) {
          Text('今天')
            .fontSize(9)
            .fontColor(tc(this.dark, '#9BAEBD', 1))
            .backgroundColor(tc(this.dark, '#F2F7FB', 0))
            .borderRadius(20)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
        }
        if (this.dayCount(d) > 0) {
          Text(`${this.dayCount(d)}`)
            .fontSize(9)
            .fontColor(tc(this.dark, '#9BAEBD', 1))
            .backgroundColor(tc(this.dark, '#F2F7FB', 0))
            .borderRadius(20)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
        }
        SymbolGlyph(sym('plus'))
          .fontSize(14)
          .fontColor([tc(this.dark, '#C3D2DE', 1)])
          .padding(2)
          .onClick(() => { this.openNew(D.key(d), 0); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 9 })

      // 日程
      ForEach(this.eventsOf(D.key(d)), (e: EventItem) => {
        Row({ space: 9 }) {
          Text(e.all_day === 1 ? '全天' : `${D.hm(e.start_at)}–${e.end_at !== null ? D.hm(e.end_at) : this.hmOf(this.minutesOf(e.start_at) + 45)}`)
            .fontSize(10)
            .fontColor(tc(this.dark, '#5E7183', 1))
            .flexShrink(0)
          Text(e.title)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(tc(this.dark, '#2C4257', 1))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (e.location !== null && e.location.length > 0) {
            Text(e.location)
              .fontSize(8.5)
              .fontColor(tk(this.dark, 'textHint'))
              .maxLines(1)
              .flexShrink(0)
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(9)
        .backgroundColor(tc(this.dark, '#F7FBFE', 0))
        .margin({ bottom: 5 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.openEdit(e.id); })
      }, (e: EventItem) => `w-${e.id}-${this.tick}`)

      // 当天到期的任务
      ForEach(this.tasksOf(D.key(d)), (t: Task) => {
        Row({ space: 9 }) {
          Text('任务').fontSize(10).fontColor(tc(this.dark, '#A8B8C6', 1)).flexShrink(0)
          Row().width(5).height(5).borderRadius(3).backgroundColor(areaColor(this.dark, t.area))
          Text(t.title)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(tc(this.dark, '#2C4257', 1))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(9)
        .backgroundColor(tc(this.dark, '#F7FBFE', 0))
        .margin({ bottom: 5 })
        .alignItems(VerticalAlign.Center)
      }, (t: Task) => `wt-${t.id}-${t.status}-${this.tick}`)

      // 空态：这天空着（周视图压成横排，对齐 .cal2-mweek.week .mw-empty）
      if (this.dayCount(d) === 0) {
        Row({ space: 7 }) {
          SymbolGlyph(sym('plus')).fontSize(13).fontColor([tc(this.dark, '#C7D8E4', 1)])
          Text('这天空着').fontSize(11).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#8FA2B3', 1))
        }
        .width('100%')
        .height(38)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .padding({ top: 11, bottom: 11 })
        .borderRadius(10)
        .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F0F8', 2), 2), style: BorderStyle.Dashed })
        .onClick(() => { this.openNew(D.key(d), 0); })
      }
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(tk(this.dark, 'card'))
    .border({ width: 1, color: tk(this.dark, 'line') })
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 10 })
  }

  private dayCount(d: Date): number {
    const k: string = D.key(d);
    return this.eventsOf(k).length + this.tasksOf(k).length;
  }

  // ── 日视图：时间轴 + 空闲块 ──
  // 日视图左侧时间轴（对齐 .cal2-scroll 里的日程块）
  @Builder dayTimeline() {
    Column() {
      // v4.4：全天日程单独一行 —— 以前在时间轴上显示成 00:00，看不出是全天
      if (this.kSelAllDay.length > 0) {
        Column({ space: 5 }) {
          Text('全天').fontSize(10).fontColor(tc(this.dark, '#5E7183', 1)).fontWeight(FontWeight.Medium)
          ForEach(this.kSelAllDay, (e: EventItem) => {
            Row({ space: 9 }) {
              Text(e.title)
                .fontSize(11.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(tc(this.dark, '#2C4257', 1))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (e.location !== null && e.location.length > 0) {
                Text(e.location).fontSize(8.5).fontColor(tc(this.dark, '#9BAEBD', 1))
              }
            }
            .width('100%')
            .padding({ left: 9, right: 9, top: 8, bottom: 8 })
            .borderRadius(9)
            .backgroundColor(tc(this.dark, '#F7FBFE', 0))
            .border({ width: { left: 3 }, color: { left: this.toneOf(e) } })
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 6 })
            .onClick(() => { this.openEdit(e.id); })
          }, (e: EventItem) => `ad-${e.id}-${this.tick}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 4 })
      }
      ForEach(this.kSelEvents, (e: EventItem) => {
        Row({ space: 10 }) {
          Column({ space: 1 }) {
            Text(D.hm(e.start_at)).fontSize(10).fontColor(tc(this.dark, '#5E7183', 1))
            if (e.end_at !== null) {
              Text(D.hm(e.end_at)).fontSize(8.5).fontColor(tc(this.dark, '#A8B8C6', 1))
            }
          }
          .width(38)
          .alignItems(HorizontalAlign.End)
          .flexShrink(0)

          Column({ space: 2 }) {
            Text(e.title)
              .fontSize(11.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(tc(this.dark, '#2C4257', 1))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (e.location !== null && e.location.length > 0) {
              Text(e.location).fontSize(8.5).fontColor(tc(this.dark, '#9BAEBD', 1)).width('100%')
            }
            // v4.12：关联的任务合并到日程这一行里
            if (this.linkedTaskTitles(e.id).length > 0) {
              Text(`任务：${this.linkedTaskTitles(e.id)}`)
                .fontSize(9).fontColor(tc(this.dark, '#7E97AC', 1)).width('100%').maxLines(2)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 9, right: 9, top: 8, bottom: 8 })
        .borderRadius(9)
        .backgroundColor(tc(this.dark, '#F7FBFE', 0))
        .border({ width: { left: 3 }, color: { left: this.toneOf(e) } })
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 6 })
        .onClick(() => { this.openEdit(e.id); })
      }, (e: EventItem) => `de-${e.id}-${this.tick}`)

      if (this.kSelEvents.length === 0 && this.kSelAllDay.length === 0) {
        Column({ space: 5 }) {
          SymbolGlyph(sym('plus')).fontSize(16).fontColor([tc(this.dark, '#C7D8E4', 1)])
          Text('这天空着').fontSize(11).fontColor(tc(this.dark, '#9BAEBD', 1))
          Text('点这里安排点什么').fontSize(9).fontColor(tc(this.dark, '#C2D0DB', 1))
        }
        .width('100%')
        .padding({ top: 20, bottom: 20 })
        .borderRadius(10)
        .border({ width: 1, color: tc(this.dark, tc(this.dark, '#DDE9F3', 2), 2), style: BorderStyle.Dashed })
        .alignItems(HorizontalAlign.Center)
        .onClick(() => { this.openNew(this.selected, 0); })
      }

      // 点时间轴空白也能新建
      Row({ space: 5 }) {
        SymbolGlyph(sym('plus')).fontSize(14).fontColor([tc(this.dark, '#9FE0DC', 1)])
        Text('点这里排一件事').fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 2 })
      .onClick(() => { this.openNew(this.selected, 0); })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 日视图右侧「这天要做」（对齐 .day-side：ds-row / ds-sec / ds-gap / ds-foot）
  @Builder daySide() {
    Card({
      title: '这天要做',
      sub: `${this.kSelTasks.length} 件`,
      bodyPadTop: 2,
      bodyPadBottom: 10
    }) {
      if (this.kSelTasks.length === 0) {
        Text('这天没有任务截止，清爽。').fontSize(8.5).fontColor(tc(this.dark, '#A8B8C6', 1)).width('100%')
      } else {
        ForEach(this.kSelTasks, (t: Task) => {
          Column({ space: 1 }) {
            Text(t.title)
              .fontSize(11).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#2C4257', 1))
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Row({ space: 5 }) {
              Text(this.taskKindTag(t))
                .fontSize(8).fontColor(tkInk(this.dark, 'brandDeep'))
                .backgroundColor(tk(this.dark, 'brandSoft')).borderRadius(5)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              Text(`${t.project !== null && t.project.length > 0 ? t.project : areaLabel(t.area)}${t.priority === 'high' ? ' · 要紧' : ''}`)
                .fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1)).layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(tc(this.dark, '#FBFDFF', 0))
          .border({ width: { left: 3 }, color: areaColor(this.dark, t.area) })
          .margin({ bottom: 6 })
          .alignItems(HorizontalAlign.Start)
          .onClick(() => { this.onNavigate('tasks'); })
        }, (t: Task) => `ds-${t.id}-${t.status}-${this.tick}`)
      }

      // .ds-sec：虚线上边框 + 小标题（合并为单元素）
      Text('空着的整块时间')
        .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).letterSpacing(0.4)
        .width('100%')
        .padding({ top: 12 })
        .margin({ top: 14, bottom: 6 })
        .border({ width: { top: 1 }, color: '#E8F1F8', style: BorderStyle.Dashed })

      if (this.kSelGaps.length === 0) {
        Text('这天排得比较满，注意留白。').fontSize(8.5).fontColor(tc(this.dark, '#A8B8C6', 1)).width('100%')
      } else {
        ForEach(this.kSelGaps.slice(0, 4), (g: number[], i: number) => {
          Row({ space: 8 }) {
            Text(`${this.hmOf(g[0])}–${this.hmOf(g[1])}`)
              .fontSize(9.5).fontColor(tc(this.dark, '#5E7183', 1))
            Blank()
            Text(`${Math.round((g[1] - g[0]) / 60 * 10) / 10} 小时`)
              .fontSize(9).fontColor(tc(this.dark, '#3AC8C2', 1)).fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(tc(this.dark, '#FBFDFF', 0))
          .border({ width: 1, color: tc(this.dark, tc(this.dark, '#D9E8F4', 2), 2), style: BorderStyle.Dashed })
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 5 })
          .onClick(() => { this.openNew(this.selected, g[0]); })
        }, (g: number[], i: number) => `gap-${i}-${g[0]}-${this.tick}`)
      }

      // .ds-foot：两个统计格
      Row({ space: 8 }) {
        Column({ space: 1 }) {
          Text(`${this.eventsOf(this.selected).length}`)
            .fontSize(14).fontColor(tc(this.dark, '#1F9E9A', 1)).fontWeight(FontWeight.Medium)
          Text('个日程').fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
        }
        .layoutWeight(1)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(tc(this.dark, '#F7FBFE', 0))
        .alignItems(HorizontalAlign.Start)

        Column({ space: 1 }) {
          Text(`${this.kSelOccupied}h`)
            .fontSize(14).fontColor(tc(this.dark, '#1F9E9A', 1)).fontWeight(FontWeight.Medium)
          Text('已占时间').fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
        }
        .layoutWeight(1)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(tc(this.dark, '#F7FBFE', 0))
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: 10 })
    }
  }

  @Builder sheetBody() {
    EventSheet({
      editingId: this.editingId,
      defaultDate: this.sheetDate,
      defaultStart: this.sheetStart,
      defaultEnd: this.sheetEnd,
      onSaved: () => {
        const wasEdit: boolean = this.editingId > 0;
        this.closeSheet();
        this.editingId = -1;
        toast(this.getUIContext(), wasEdit ? '日程已更新' : '排上了');
      },
      onCancel: () => {
        this.closeSheet();
        this.editingId = -1;
      }
    })
  }

  /** v4.6：宽屏（平板/折叠屏）走「遮罩 + 居中卡片」，窄屏还是底部抽屉 */
  @Builder sheetContent() {
    SheetFrame({
      wide: this.wideMode(),
      onClose: () => { this.closeSheet(); this.editingId = -1; },
      content: () => { this.sheetBody(); }
    })
  }

  @Builder pageTop() {
    TopBar({
      primaryText: '新日程',
      onPrimary: () => { this.openNew(this.view === 0 ? D.today() : this.selected, 0); },
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.selected = D.today(); this.weekOffset = 0; this.view = 1; this.recalc(); }
    })
      .width('100%')
  }

  build() {
    Stack() {

      Scroll() {
        Column() {
          Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

          this.pageTop()

          // page-head
          Column({ space: 5 }) {
            Text('CALENDAR · 日历安排').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
            Text(this.view === 0 ? '这一周，先占住时间。' : '这一天，先占住时间。')
              .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
            Text(this.view === 0
              // v4.4：App 里没有拖动改时间的功能，别再承诺
              ? `${this.kWeekLabel} · ${this.kWeekCount} 个日程`
              : `${D.md(this.selected)} ${D.weekdayFull(D.parse(this.selected))} · ${this.kSelEvents.length + this.kSelAllDay.length} 个日程`)
              .fontSize(11)
              .fontColor(tk(this.dark, 'textSub'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 14, bottom: 12 })

          // 视图切换 + 翻页
          Row({ space: 6 }) {
            Chip({ text: '周', active: this.view === 0, onTap: () => { this.view = 0; } })
            Chip({ text: '日', active: this.view === 1, onTap: () => { this.view = 1; } })
            Blank()
            Row() {
              // v4.23：arrow_left 在 fs16 墨迹 12.0x12.0vp，满足 2.1.4.3.2
              SymbolGlyph(sym('left')).fontSize(16).fontColor([tc(this.dark, '#7C8F9F', 1)])
            }
            .width(28).height(28).borderRadius(8)
            .backgroundColor(tk(this.dark, 'card'))
            .border({ width: 1, color: tk(this.dark, 'line') })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              if (this.view === 0) {
                this.weekOffset -= 1;
                this.recalc();
              } else {
                this.selected = D.key(D.dateAdd(D.parse(this.selected), -1));
                this.recalc();
              }
            })

            Text('今天')
              .fontSize(11)
              .fontColor(tc(this.dark, '#6A7F92', 1))
              .height(28)
              .padding({ left: 10, right: 10 })
              .borderRadius(8)
              .backgroundColor(tk(this.dark, 'card'))
              .border({ width: 1, color: tk(this.dark, 'line') })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.weekOffset = 0;
                this.selected = D.today();
                this.recalc();
              })

            Row() {
              // v4.23：arrow_right 在 fs16 墨迹 14.3x12.0vp，满足 2.1.4.3.2
              SymbolGlyph(sym('right')).fontSize(16).fontColor([tc(this.dark, '#7C8F9F', 1)])
            }
            .width(28).height(28).borderRadius(8)
            .backgroundColor(tk(this.dark, 'card'))
            .border({ width: 1, color: tk(this.dark, 'line') })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              if (this.view === 0) {
                this.weekOffset += 1;
                this.recalc();
              } else {
                this.selected = D.key(D.dateAdd(D.parse(this.selected), 1));
                this.recalc();
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 12 })

          // 周视图：每天一卡
          if (this.view === 0) {
            Column() {
              ForEach(this.weekDays(), (d: Date) => {
                this.dayCard(d)
              }, (d: Date) => `wd-${D.key(d)}-${this.tick}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          } else {
            // 日视图：时间轴卡 + 「这天要做」卡（对齐工作台 day-side）
            Card({
              title: `${D.md(this.selected)} ${D.weekdayFull(D.parse(this.selected))}`,
              // v4.12：跟日程关联上的任务已经合并进日程那一行，计数不再重复算
              sub: `${this.eventsOf(this.selected).length} 个日程 · ${this.kSelTasks.length} 件任务`,
              headMode: 'add',
              headText: '排日程',
              onHead: () => { this.openNew(this.selected, 0); },
              bodyPadBottom: 12
            }) {
              this.dayTimeline()
            }

            Column().width('100%').height(12)

            this.daySide()
          }

          // 工作台手机端 .cal2-card .cal2-foot{display:none}：去掉无实现的提示条，只留底部留白
          Column().width('100%').height(S.pageBottom)
        }
        .width('100%')
        .padding({ left: S.pagePad, right: S.pagePad, top: S.pageTop })
        .alignItems(HorizontalAlign.Start)
      }
      .onScrollEdge(onEdgeScrolled)
      .onWillScroll(onEdgeWillScroll)
      .align(Alignment.TopStart)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .constraintSize({ maxWidth: 1240 })
      .backgroundColor(tk(this.dark, 'bg'))
      .edgeEffect(EdgeEffect.Spring)
      .bindSheet($$this.showSheet, this.sheetContent(), {
        // v4.26：宽屏时给「窗口高度」这个绝对值，别写 '100%'
        //   （bindSheet 面板里百分比会被当成内容高度，面板撑不满、卡片不居中）
        // v4.26：宽屏时用 SheetSize.LARGE（面板几乎占满屏幕），窄屏还是贴底抽屉。
        //   之前写 '100%'，在 bindSheet 面板里百分比被解析成「内容高度」，
        //   面板只有 864vp（竖屏实测），卡片被顶到下半屏、遮罩也只盖住下半屏。
          height: SheetSize.FIT_CONTENT,
        dragBar: !this.wideMode(),
        showClose: false,
        backgroundColor: Color.Transparent,   // 面板透明，弹层内容自己带圆角白底
        width: '100%'})
  

      // v4.26（平板竖屏）：宽屏的弹层在页面里自己画 —— bindSheet 的面板高度是
      //   平台按「内容高度」算的（竖屏实测只有 560vp），卡片会被裁掉底部按钮，
      //   自己画的遮罩也只能盖住面板那一块。窄屏仍然走 bindSheet 底部抽屉。
      if (this.wideMode() && this.wideOpen) {
        this.sheetContent()
      }
    }
    .width('100%')
    .height('100%')
  }
}
