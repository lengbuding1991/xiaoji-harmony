// 成长总览（首页）
// 结构逐块对齐「个人工作台」components/Dashboard.tsx：hello → 5 个 KPI → 趋势 → 投入 → 最近任务
// → 月历 → 核心模块 → 本周小结 → 灵感派 → 今日一句 → 本周安排（任务+日程，日历条可点）。
// v2.9：底部「任务看板」整块已删（和任务面板重复，用户要求）。
// v3.0：hello 下面加了一颗「全部内容」胶囊 → 跳 AllView（任务/灵感/日程/项目/复盘/习惯 一处看全）。
// 手机上全部单列竖排（工作台在 <=820px 时 .home-grid 也是单列）。
import { Store, isConsumedRepeat } from '../store/Store';
import { areaColor, areaLabel, barBg, barColor, brandGradient, C, catBg, catColor, S, tc, tk, tkInk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { toast } from '../utils/Toast';
import { Card } from '../components/Card';
import { LineChart } from '../components/LineChart';
import { Donut, DonutLegend, ringPiece, RingPiece } from '../components/Donut';
import { Kpi, ModTile, SecHead, MonthCal, CalCell, calCell, MiniBars, WeekGantt, GanttBar, ganttBar } from '../components/Widgets';
import { R } from '../utils/Responsive';
import { IconBox } from '../components/IconBox';
import { sym } from '../components/Icon';
import { Task, Note, TaskCreate, TaskStatus, EventItem, HabitView } from '../api/Types';
import { StatusDot } from '../components/StatusDot';
import { TopBar } from '../components/TopBar';
import { display } from '@kit.ArkUI';
import { TaskSheet } from '../components/TaskSheet';
import { SheetFrame } from '../components/SheetFrame';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

interface InvestItem {
  area: string;
  label: string;
  hex: string;
  v: number;
  pct: number;
}

interface CandItem {
  id: number;
  title: string;
  pct: number;
  color: string;
}

@Component
export struct HomeView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tick: number = 0;
  @State tasks: Task[] = [];
  @State notes: Note[] = [];
  /** 日程（v2.9：首页也要看到日历安排里的东西） */
  @State events: EventItem[] = [];
  /** 习惯（v4.12：首页「习惯打卡」卡要用） */
  @State habits: HabitView[] = [];
  /** 本周安排里选中的那天（-1 = 看整周） */
  @State dayPick: number = -1;
  @State loaded: boolean = false;
  @State refreshing: boolean = false;
  @State showAdd: boolean = false;
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
      this.showAdd = true;
    }
  }

  private closeSheet(): void {
    this.showAdd = false;
    this.wideOpen = false;
    AppStorage.setOrCreate<boolean>('wb_fab_hide', false);
  }

  /** v4.26：宽屏时铺在页面最上层的遮罩 + 居中卡片 */
  @Builder
  wideOverlay() {
    if (this.wideMode() && this.wideOpen) {
      this.addSheet()
    }
  }

  @State trendRange: number = 0;     // 0=本周 1=上周
  @State investRange: number = 0;    // 0=本周 1=本月
  @State weekOffset: number = 0;
  @State spin: number = 0;
  // v4.6：宽屏档位（0 手机 / 1 小平板 / 2 平板）。变了这一页要重画
  @StorageLink('wb_layout') layoutMode: number = 0;
  // v4.6：内容区宽度（扣掉左侧导航后的实际宽度），决定 KPI 排几列
  @StorageLink('wb_content_w') contentW: number = 0;
  @State calOffset: number = 0;      // 月历偏移（0=本月）
  // ── v4.2：派生数值预计算 ────────────────────────────────
  // ArkUI V1 只刷新「属性表达式里直接读过 state」的节点；
  // 方法调用里读 state（this.todayPct()）不算依赖 ⇒ 先算好写进 @State 再显示。
  // v4.12：首页 KPI 全部改成「总任务」口径（用户拍板）：
  //   「我的任务」= 全部任务几项；「完成率」= 已完成 / 总任务。
  //   长期任务（没写截止日期）也永远在分母里 —— 它没做完就一直欠着；
  //   写了截止日期又没做完的，照样算逾期（任务面板里标红）。
  @State kAllTasks: number = 0;       // 总任务数
  @State kDoneCount: number = 0;      // 已完成数
  @State kOpenCount: number = 0;      // 未完成数
  @State kAllPct: number = 0;         // 总完成率（已完成 / 总任务）
  @State kPctSub: string = '';        // 完成率副文案
  @State kDueTodayOpen: number = 0;   // 今日到期且未完成（页头 N）
  @State kHeaderTitle: string = '';   // 页头标题
  @State kHeaderSub: string = '';     // 页头副文案
  @State kHabitStreak: number = 0;    // 各习惯里最长的连续打卡天数
  @State kHabitPending: number = 0;   // 今天还没打卡的习惯数
  @State kHabitSub: string = '';
  @State kHabitPct: number = 0;
  @State kHabitBest: number = 0;    // 历史最长连续打卡天数
  @State kDoneAll: number = 0;        // 累计完成
  @State kOpenAll: number = 0;        // 未完成总数
  @State kFocusH: string = '0.0';     // 本周专注小时
  @State kFocusPct: number = 0;
  @State kWeekDone: number = 0;       // 本周完成
  @State kWeekPoints: number = 0;     // 本周积分
  @State kPoints: number = 0;         // 成长积分（累计）
  @State kPointsPct: number = 0;
  @State kTrendValues: number[] = [];
  @State kTrendLabels: string[] = [];
  @State kTrendSum: string = '0.0';
  @State kInvestItems: InvestItem[] = [];
  @State kInvestPieces: RingPiece[] = [];
  @State kInvestTotal: string = '0.0';
  @State kCalCells: CalCell[] = [];
  @State kCalLabel: string = '';
  @State kCalDone: number = 0;
  @State kSummary: string = '';
  @State kQuote: string = '';
  @State kRecentCount: number = 0;
  @State kCandItems: CandItem[] = [];
  @State kCandPieces: RingPiece[] = [];
  @State kCandCount: number = 0;
  @State kWeekArrCount: number = 0;
  @State kWeekDayNums: string[] = [];
  @State kWeekBars: GanttBar[] = [];
  @State kWeekRange: string = '';
  @State kTodayIdx: number = 0;
  @State kUserName: string = '';       // 设置里的「称呼」
  // v4.4：下面这些以前是在 build() 里直接调方法拿的（weekEvents() / weekTasks() /
  // dayEventsAt() / recentTasks()…）。ArkUI V1 里「方法调用中读 state」不算依赖，
  // 数据变了这些地方不会自己更新 ⇒ 全部改成预计算进 @State。
  @State kWeekEvents: EventItem[] = [];
  @State kWeekTasks: Task[] = [];
  @State kDayEvents: EventItem[] = [];
  @State kDayTasks: Task[] = [];
  @State kRecent: Task[] = [];
  @State kTotalTasks: number = 0;
  @State kActiveNotes: number = 0;
  onNavigate: (page: string) => void = () => {};
  private unsub: () => void = () => {};

  /** v4.6：宽屏？ */
  private wideMode(): boolean {
    return this.layoutMode >= 1;
  }

  private syncStore(): void {
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.events = Store.I.events;
    this.habits = Store.I.habits;
    this.loaded = Store.I.loaded;
    this.recalc();
  }

  /** v4.2：把所有派生数值算好写进 @State（UI 里只直接读 state） */
  private recalc(): void {
    const open: Task[] = this.openTasks();
    const doneAll: Task[] = this.doneTasks();

    // v4.12：首页 KPI 全部改成「总任务」口径（用户拍板）：
    //   「我的任务」= 全部任务几项；「完成率」= 已完成 / 总任务。
    //   长期任务（没写截止日期）也永远在分母里 —— 它没做完就一直欠着；
    //   写了截止日期又没做完的，照样算逾期（任务面板里标红）。
    // v4.12：总数也不含已消耗的重复原件（它已经不算一条真任务）
    let consumed: number = 0;
    for (const t of this.tasks) {
      if (isConsumedRepeat(t)) { consumed += 1; }
    }
    this.kAllTasks = this.tasks.length - consumed;
    this.kDoneCount = doneAll.length;
    this.kOpenCount = open.length;
    this.kAllPct = this.kAllTasks > 0 ? Math.round(doneAll.length * 100 / this.kAllTasks) : 0;
    this.kPctSub = this.kAllTasks === 0
      ? '还没有任务'
      : (this.kOpenCount > 0 ? `还剩 ${this.kOpenCount} 件没做完` : '全部做完了');

    // 页头 N：今日到期且还没做完的件数
    const todayKey: string = D.key(new Date());
    let dueOpen: number = 0;
    for (const t of open) {
      if (t.due_date !== null && D.dateOf(t.due_date) === todayKey) { dueOpen += 1; }
    }
    this.kDueTodayOpen = dueOpen;
    this.kHeaderTitle = dueOpen > 0 ? `今天，先做 ${dueOpen} 件要紧事。` : '今天没有到期的事。';
    this.kHeaderSub = dueOpen > 0
      ? '其余都是加分项，慢慢来。'
      : '想记点什么，去「记录灵感」写一条。';

    // 习惯打卡：各习惯里当前连续天数的最大值（今天还没打卡不打断）；另外算历史最长
    let maxStreak: number = 0;
    let maxBest: number = 0;
    let pending: number = 0;
    for (const h of this.habits) {
      if (h.streak > maxStreak) { maxStreak = h.streak; }
      if (h.bestStreak > maxBest) { maxBest = h.bestStreak; }
      if (!h.doneToday) { pending += 1; }
    }
    this.kHabitStreak = maxStreak;
    this.kHabitPending = pending;
    // v4.13：副文案 = 今日待打卡 + 历史最长（大数字仍是「当前连续」）
    this.kHabitSub = this.habits.length === 0
      ? '还没有习惯'
      : ((pending === 0 ? '今天的习惯都打卡了' : `今天还有 ${pending} 个没打卡`)
        + (maxBest > 0 ? ` · 历史最长 ${maxBest} 天` : ''));
    this.kHabitBest = maxBest;
    this.kHabitPct = Math.min(100, Math.round(maxStreak / 7 * 100));

    this.kDoneAll = doneAll.length;
    this.kOpenAll = open.length;

    this.kWeekDone = this.weekDone().length;
    const fmin: number = this.focusMin();
    this.kFocusH = (fmin / 60).toFixed(1);
    // 目标：每天 2 小时 × 7 天 = 840 分钟
    this.kFocusPct = Math.min(100, Math.round(fmin / 840 * 100));
    // v4.4：归档的记录不该再计分（Store.I.notes 是含归档的）
    this.kActiveNotes = this.activeNotes().length;
    this.kPoints = doneAll.length * 10 + this.kActiveNotes * 2;
    // 本周积分（进度条目标 30 分 / 周）
    let wNotes: number = 0;
    const wStart: string = D.weekStart();
    for (const n of this.notes) {
      if (n.archived === 1) { continue; }
      if (n.updated_at !== null && D.dateOf(n.updated_at) >= wStart) { wNotes += 1; }
    }
    this.kWeekPoints = this.kWeekDone * 10 + wNotes * 2;
    this.kPointsPct = Math.min(100, Math.round(this.kWeekPoints / 30 * 100));

    const tv: number[] = this.trendValues();
    this.kTrendValues = tv;
    this.kTrendLabels = this.trendLabels();
    let sum: number = 0;
    for (const v of tv) { sum += v; }
    this.kTrendSum = sum.toFixed(1);

    const inv: InvestItem[] = this.invest();
    this.kInvestItems = inv;
    const pieces: RingPiece[] = [];
    for (const i of inv) { pieces.push(ringPiece(i.label, i.v, i.hex, i.pct)); }
    this.kInvestPieces = pieces;
    let tot: number = 0;
    for (const i of inv) { tot += i.v; }
    this.kInvestTotal = tot.toFixed(1);

    this.kCalCells = this.calCells();
    this.kCalLabel = this.calLabel();
    this.kCalDone = this.calDoneCount();
    this.kSummary = this.summaryText();

    const q: Note | null = this.quoteNote();
    this.kQuote = q !== null ? `${(q as Note).content.substring(0, 40)}…` : '';

    const recent: Task[] = this.recentTasks();
    this.kRecent = recent;
    this.kRecentCount = recent.length;
    this.kTotalTasks = this.tasks.length;
    const cands: CandItem[] = this.candidates();
    this.kCandItems = cands;
    const cpieces: RingPiece[] = [];
    for (const c of cands) { cpieces.push(ringPiece(c.title, c.pct, c.color, c.pct)); }
    this.kCandPieces = cpieces;
    this.kCandCount = cands.length;

    // v4.4：本周安排 / 选中某天，全部先算好
    this.kWeekTasks = this.weekTasks();
    this.kWeekEvents = this.weekEvents();
    this.kWeekArrCount = this.kWeekTasks.length + this.kWeekEvents.length;
    this.kDayTasks = this.dayPick >= 0 ? this.dayTasksAt(this.dayPick) : [];
    this.kDayEvents = this.dayPick >= 0 ? this.dayEventsAt(this.dayPick) : [];
    this.kWeekDayNums = this.weekDayNums();
    this.kWeekBars = this.weekBars();
    this.kWeekRange = this.weekRangeLabel();
    this.kTodayIdx = this.todayIdxInWeek();
    this.kUserName = Store.I.settings.user_name;
  }

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate<boolean>('wb_fab_hide', false);
    this.unsub();
  }

  // ── 计算口径全部照抄 Dashboard.tsx ──
  private openTasks(): Task[] {
    return this.tasks.filter((t: Task) => t.status !== 'done');
  }

  private doneTasks(): Task[] {
    // v4.12：重复任务做完的「原件」不计入统计
    return this.tasks.filter((t: Task) => t.status === 'done' && !isConsumedRepeat(t));
  }

  /** v4.5：趋势图的末点气泡正好落在右下角悬浮按钮下面 → 把图表位置报上去，让按钮自己让开 */
  private chartArea(oldA: Area, newA: Area): void {
    const x: number = this.numOf(newA.globalPosition.x);
    const y: number = this.numOf(newA.globalPosition.y);
    const w: number = this.numOf(newA.width);
    const h: number = this.numOf(newA.height);
    let sw: number = 360;
    let sh: number = 780;
    try {
      const d = display.getDefaultDisplaySync();
      sw = this.getUIContext().px2vp(d.width);
      sh = this.getUIContext().px2vp(d.height);
    } catch (e) {
      sw = 360; sh = 780;
    }
    // 悬浮按钮的矩形（vp）：右下角，距右边 16、下边距 68、直径 42
    const fx1: number = sw - 58; const fx2: number = sw - 16;
    const fy1: number = sh - 110; const fy2: number = sh - 68;
    // 末点气泡的真实位置（LineChart 报来的画布坐标 + 画布在窗口里的位置）
    const bl: number[] = this.bubbleLocal;
    const bx1: number = x + bl[0]; const bx2: number = bx1 + bl[2];
    const by1: number = y + bl[1]; const by2: number = by1 + bl[3];
    const hit: boolean = bl[2] > 0 && !(bx2 < fx1 || bx1 > fx2 || by2 < fy1 || by1 > fy2);
    AppStorage.setOrCreate<boolean>('wb_fab_hide', hit);
  }

  private bubbleLocal: number[] = [0, 0, 0, 0];   // 末点气泡在画布里的位置（vp）

  private numOf(v: Length | undefined): number {
    if (v === undefined) { return 0; }
    if (typeof v === 'string') { return 0; }
    return v as number;
  }

  /** 上周完成的件数（用来跟本周比） */
  private lastWeekDoneCount(): number {
    const start: Date = D.dateAdd(D.parse(D.weekStart()), -7);
    const end: Date = D.parse(D.weekStart());
    let n: number = 0;
    for (const t of this.doneTasks()) {
      if (t.done_at === null) { continue; }
      const d: Date = D.parse(t.done_at);
      if (d.getTime() >= start.getTime() && d.getTime() < end.getTime()) { n += 1; }
    }
    return n;
  }

  private weekDone(): Task[] {
    const ws = D.weekStart();
    return this.doneTasks().filter((t: Task) => t.done_at !== null && D.dateOf(t.done_at) >= ws);
  }

  /** v4.12：没填「预计分钟」的任务不再按 20 分钟编 —— 宁可少算，不要造假 */
  private focusMin(): number {
    let n = 0;
    for (const t of this.weekDone()) { if (t.estimate_min !== null) { n += t.estimate_min; } }
    return n;
  }

  /** 没归档的记录（归档的不该再计分、不该再出现在首页） */
  private activeNotes(): Note[] {
    const out: Note[] = [];
    for (const n of this.notes) {
      if (n.archived === 1) { continue; }
      out.push(n);
    }
    return out;
  }

  /** 7 天专注小时（按 done_at 的 estimate_min 求和） */
  private trendValues(): number[] {
    const end: Date = this.trendRange === 1 ? D.dateAdd(new Date(), -7) : new Date();
    const out: number[] = [];
    for (let i = 0; i < 7; i++) {
      const d = D.dateAdd(end, -(6 - i));
      let mins = 0;
      for (const t of this.doneTasks()) {
        if (t.done_at !== null && D.sameDay(t.done_at, d)) {
          if (t.estimate_min !== null) { mins += t.estimate_min; }
        }
      }
      out.push(Math.round(mins / 60 * 10) / 10);
    }
    return out;
  }

  private trendLabels(): string[] {
    const end: Date = this.trendRange === 1 ? D.dateAdd(new Date(), -7) : new Date();
    const out: string[] = [];
    for (let i = 0; i < 7; i++) { out.push(D.slashMd(D.dateAdd(end, -(6 - i)))); }
    return out;
  }

  private trendSum(): string {
    let s = 0;
    for (const v of this.trendValues()) { s += v; }
    return s.toFixed(1);
  }

  /** 本周已排期任务 */
  private weekTasks(): Task[] {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    const we: Date = D.dateAdd(ws, 7);
    return this.tasks.filter((t: Task) => {
      if (t.scheduled_start === null) { return false; }
      const s = D.parse(t.scheduled_start);
      return s.getTime() >= ws.getTime() && s.getTime() < we.getTime();
    });
  }

  private weekBars(): GanttBar[] {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    const out: GanttBar[] = [];
    for (const t of this.weekTasks()) {
      const s = D.parse(t.scheduled_start as string);
      const e = t.scheduled_end !== null ? D.parse(t.scheduled_end) : s;
      let si = D.diffDays(s, ws);
      let ei = D.diffDays(e, ws);
      si = Math.max(0, Math.min(6, si));
      ei = Math.max(si, Math.min(6, ei));
      out.push(ganttBar(t.title, si, ei, barBg(this.dark, t.area), barColor(this.dark, t.area), `${t.id}`));
    }
    // v4.4：日程也画进甘特条。卡片上写「N 件安排」是任务 + 日程，
    // 甘特条只画任务的话，两边对不上（而且点某天看到的日程在条上找不到）。
    for (const e of this.weekEvents()) {
      const s = D.parse(e.start_at);
      const en = (e.end_at !== null && e.end_at.length > 0) ? D.parse(e.end_at) : s;
      let si = D.diffDays(s, ws);
      let ei = D.diffDays(en, ws);
      si = Math.max(0, Math.min(6, si));
      ei = Math.max(si, Math.min(6, ei));
      out.push(ganttBar(e.title, si, ei, '#F2ECFF', '#704DD2', `e${e.id}`));
    }
    // 按开始时间升序 —— 以前不排序，甘特条上的条是乱的
    for (let i = 0; i < out.length; i++) {
      for (let j = i + 1; j < out.length; j++) {
        if (out[j].startIdx < out[i].startIdx) {
          const tmp = out[i]; out[i] = out[j]; out[j] = tmp;
        }
      }
    }
    return out;
  }

  private weekDayNums(): string[] {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    const out: string[] = [];
    for (let i = 0; i < 7; i++) { out.push(D.dd(D.dateAdd(ws, i))); }
    return out;
  }

  private weekRangeLabel(): string {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    return `${D.dotMd(ws)} – ${D.dotMd(D.dateAdd(ws, 6))}`;
  }

  private todayIdxInWeek(): number {
    return D.diffDays(new Date(), D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7));
  }

  /** 模块投入占比 */
  private invest(): InvestItem[] {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    const we: Date = D.dateAdd(ws, 7);
    const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const monthEnd = new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0);
    const source: Task[] = [];
    if (this.investRange === 1) {
      for (const t of this.tasks) {
        if (t.scheduled_start === null) { continue; }
        const d = D.parse(t.scheduled_start);
        if (d.getTime() >= monthStart.getTime() && d.getTime() <= monthEnd.getTime()) { source.push(t); }
      }
    } else {
      for (const t of this.weekTasks()) { source.push(t); }
    }
    const areas: string[] = [];
    const vals: number[] = [];
    for (const t of source) {
      const s = D.parse(t.scheduled_start as string);
      const e = t.scheduled_end !== null ? D.parse(t.scheduled_end) : s;
      const hv = Math.max(0.5, D.diffDays(e, s) + 1);
      const i = areas.indexOf(t.area);
      if (i >= 0) { vals[i] += hv; } else { areas.push(t.area); vals.push(hv); }
    }
    if (areas.length === 0) {
      for (const t of this.openTasks()) {
        const i = areas.indexOf(t.area);
        if (i >= 0) { vals[i] += 1; } else { areas.push(t.area); vals.push(1); }
      }
    }
    // 按值降序
    for (let i = 0; i < vals.length; i++) {
      for (let j = i + 1; j < vals.length; j++) {
        if (vals[j] > vals[i]) {
          const tv = vals[i]; vals[i] = vals[j]; vals[j] = tv;
          const ta = areas[i]; areas[i] = areas[j]; areas[j] = ta;
        }
      }
    }
    let total = 0;
    for (const v of vals) { total += v; }
    if (total === 0) { total = 1; }
    const out: InvestItem[] = [];
    for (let i = 0; i < areas.length; i++) {
      out.push({
        area: areas[i],
        label: areaLabel(areas[i]),
        hex: areaColor(this.dark, areas[i]),
        v: vals[i],
        pct: Math.round(vals[i] / total * 100)
      });
    }
    return out;
  }

  private investTotal(): string {
    let n = 0;
    for (const i of this.invest()) { n += i.v; }
    return n.toFixed(1);
  }

  private investPieces(): RingPiece[] {
    const out: RingPiece[] = [];
    for (const i of this.invest()) { out.push(ringPiece(i.label, i.v, i.hex, i.pct)); }
    return out;
  }

  /**
   * 灵感派（v2.8 改成显示「记录灵感」里的内容，不再是待办任务）。
   * 打分规则：置顶 +3、正文够长 +1、有标签 +1、今天/昨天刚记的 +2、最近一周记的 +1。
   */
  private candidates(): CandItem[] {
    const list: Note[] = [];
    const scores: number[] = [];
    const q: Note | null = this.quoteNote();
    const quoteId: number = q !== null ? (q as Note).id : -1;
    for (const n of this.notes) {
      if (n.archived === 1) { continue; }
      // v4.4：「今日一句」已经显示了这条，灵感派就别再显示一遍
      if (n.id === quoteId) { continue; }
      let s = 1;
      if (n.pinned === 1) { s += 3; }
      const body: string = n.content !== null ? n.content.trim() : '';
      if (body.length > 20) { s += 1; }
      if (n.tags !== null && n.tags.length > 0) { s += 1; }
      if (n.updated_at !== null && n.updated_at.length >= 10) {
        const days: number = D.diffDays(new Date(), D.parse(n.updated_at));
        if (days <= 1) { s += 2; } else if (days <= 7) { s += 1; }
      }
      list.push(n);
      scores.push(s);
    }
    // 冒泡排序（ArkTS 不接受比较器函数）
    for (let i = 0; i < scores.length; i++) {
      for (let j = i + 1; j < scores.length; j++) {
        if (scores[j] > scores[i]) {
          const ts = scores[i]; scores[i] = scores[j]; scores[j] = ts;
          const tt = list[i]; list[i] = list[j]; list[j] = tt;
        }
      }
    }
    const n: number = Math.min(5, list.length);
    let sum = 0;
    for (let i = 0; i < n; i++) { sum += scores[i]; }
    if (sum === 0) { sum = 1; }
    const palette: string[] = ['#12706B', '#1A6499', '#6650C8', '#A54A1E', '#8A5A0F'];
    const out: CandItem[] = [];
    // spin 用来「换一批」：整体轮转起始位置
    for (let k = 0; k < n; k++) {
      const i: number = (k + this.spin) % n;
      out.push({
        id: list[i].id,
        title: this.noteTitle(list[i]),
        pct: Math.round(scores[i] / sum * 100),
        color: palette[k % palette.length]
      });
    }
    return out;
  }

  /** 记录没起标题时，用正文前 14 个字顶上 */
  private noteTitle(n: Note): string {
    if (n.title !== null && n.title.trim().length > 0) { return n.title.trim(); }
    const body: string = n.content !== null ? n.content.trim() : '';
    if (body.length <= 14) { return body; }
    return `${body.substring(0, 14)}…`;
  }

  /**
   * 最近任务（v2.9）：
   * 只要「还没做完的」，按时间排序（到期日 → 排期开始 → 创建时间，越早越靠前），
   * 取最近 5 条。任务面板里加了新任务，这里立刻就能看到。
   */
  private recentTasks(): Task[] {
    const list: Task[] = [];
    const keys: string[] = [];
    for (const t of this.tasks) {
      if (t.status === 'done') { continue; }
      let k: string = '';
      if (t.due_date !== null && t.due_date.length > 0) {
        k = t.due_date.slice(0, 10);
      } else if (t.scheduled_start !== null && t.scheduled_start.length > 0) {
        k = t.scheduled_start.slice(0, 10);
      } else if (t.created_at !== null && t.created_at.length > 0) {
        k = t.created_at.slice(0, 10);
      }
      list.push(t);
      keys.push(k.length > 0 ? k : '9999-12-31');
    }
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        if (keys[j] < keys[i]) {
          const tk = keys[i]; keys[i] = keys[j]; keys[j] = tk;
          const tt = list[i]; list[i] = list[j]; list[j] = tt;
        }
      }
    }
    return list.slice(0, 5);
  }

  /** 月历格子 */
  private calCells(): CalCell[] {
    const base = new Date(new Date().getFullYear(), new Date().getMonth() + this.calOffset, 1);
    const y = base.getFullYear();
    const m = base.getMonth() + 1;
    const grid = D.monthGrid(y, m);
    const today = new Date();
    const out: CalCell[] = [];
    for (const n of grid) {
      if (n === 0) {
        out.push(calCell(0, true, false, false, 0, 0));
        continue;
      }
      const d = new Date(y, m - 1, n);
      const isToday = D.diffDays(d, today) === 0;
      let has = false;
      let total = 0;
      let done = 0;
      for (const t of this.tasks) {
        let onDay = false;
        if (t.due_date !== null && D.sameDay(t.due_date, d)) { onDay = true; }
        if (t.scheduled_start !== null && D.sameDay(t.scheduled_start, d)) { onDay = true; }
        if (onDay) { has = true; total += 1; }
        // 当天完成的：按完成时间落在这一天算（v4.12：已消耗的重复原件不算）
        if (t.status === 'done' && !isConsumedRepeat(t) && t.done_at !== null && D.sameDay(t.done_at, d)) { done += 1; }
      }
      out.push(calCell(n, false, has, isToday, done, total));
    }
    return out;
  }

  /** 本周完成了几项（当前显示的那个月） */
  private calDoneCount(): number {
    const base = new Date(new Date().getFullYear(), new Date().getMonth() + this.calOffset, 1);
    const y = base.getFullYear();
    const m = base.getMonth() + 1;
    let n = 0;
    for (const t of this.doneTasks()) {
      if (t.done_at === null || t.done_at.length < 10) { continue; }
      const d = D.parse(t.done_at);
      if (d.getFullYear() === y && d.getMonth() + 1 === m) { n += 1; }
    }
    return n;
  }

  /** 本周日程（event）——日历安排里的那些 */
  private weekEvents(): EventItem[] {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    const we: Date = D.dateAdd(ws, 7);
    const list: EventItem[] = [];
    for (const e of this.events) {
      const d = D.parse(e.start_at);
      if (d.getTime() >= ws.getTime() && d.getTime() < we.getTime()) { list.push(e); }
    }
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        if (list[j].start_at < list[i].start_at) {
          const t = list[i]; list[i] = list[j]; list[j] = t;
        }
      }
    }
    return list;
  }

  /** 选中那天的日期（yyyy-MM-dd） */
  private dayKeyAt(idx: number): string {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    return D.key(D.dateAdd(ws, idx));
  }

  /** 选中那天的日程 */
  private dayEventsAt(idx: number): EventItem[] {
    const key = this.dayKeyAt(idx);
    const list: EventItem[] = [];
    for (const e of this.events) {
      if (D.dateOf(e.start_at) === key) { list.push(e); }
    }
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        if (list[j].start_at < list[i].start_at) {
          const t = list[i]; list[i] = list[j]; list[j] = t;
        }
      }
    }
    return list;
  }

  /** 选中那天的任务（到期或排期在那天） */
  private dayTasksAt(idx: number): Task[] {
    const key = this.dayKeyAt(idx);
    const list: Task[] = [];
    for (const t of this.tasks) {
      if (t.due_date !== null && D.dateOf(t.due_date) === key) { list.push(t); continue; }
      if (t.scheduled_start !== null && D.dateOf(t.scheduled_start) === key) { list.push(t); }
    }
    return list;
  }

  /** 选中那天的标题 */
  private dayPickLabel(): string {
    if (this.dayPick < 0) { return ''; }
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    const d = D.dateAdd(ws, this.dayPick);
    const wd: string = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][this.dayPick];
    return `${d.getMonth() + 1} 月 ${d.getDate()} 日 · ${wd}`;
  }

  private calLabel(): string {
    const d = new Date(new Date().getFullYear(), new Date().getMonth() + this.calOffset, 1);
    return `${d.getFullYear()} 年 ${d.getMonth() + 1} 月`;
  }

  private summaryText(): string {
    const inv = this.invest();
    const parts: string[] = [];
    for (let i = 0; i < Math.min(3, inv.length); i++) { parts.push(inv[i].label); }
    const where: string = parts.length > 0 ? parts.join('、') : '任务';
    const tail: string = this.kWeekDone >= this.lastWeekDoneCount()
      ? '比上周更稳，保持这个节奏。'
      : '比上周松一点，先挑一件最小的事启动。';
    return `本周你在${where}上投入较多，完成 ${this.weekDone().length} 件、记录 ${this.notes.length} 条。${tail}`;
  }

  private quoteNote(): Note | null {
    for (const n of this.notes) {
      if (n.content !== null && n.content.trim().length > 8) { return n; }
    }
    return null;
  }

  /** 状态圈点击：待办 → 进行中 → 完成 → 待办（v2.8） */
  private cycleStatus(t: Task): void {
    const next: TaskStatus = t.status === 'todo' ? 'doing' : (t.status === 'doing' ? 'done' : 'todo');
    const label: string = next === 'done' ? '完成了' : (next === 'doing' ? '开始做了' : '退回待办了');
    Store.I.setTaskStatus(t.id, next).catch(() => {
      toast(this.getUIContext(), '状态没改成，检查网络再试');
    });
    toast(this.getUIContext(), `「${t.title}」${label}`);
  }

  private async doRefresh(): Promise<void> {
    await Store.I.loadAll();
    this.refreshing = false;
  }

  // ── 小部件 ──
  /** 首页一行两块的排列方向：3 列时横排，1/2 列时竖排（手机外观不变） */
  /** v4.6 宽屏网格：列数 >= 3 时按网页端 .home-grid 的 2:1 跨度 + 14vp 真实间隙排 */
  /** v4.6：宽屏首页网格 —— 照网页端 .home-grid（3 列 + 14vp 间距 + 同行等高） */
  // 宽屏同行等高：各卡上报内容高度 → 取同行最大值 → 回填该行卡片的固定高度
  @State contentH: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  @State rowH: number[] = [0, 0, 0, 0];

  private setContentH(idx: number, h: number): void {
    if (!this.gridWide()) {
      return;
    }
    const arr: number[] = this.contentH.slice();
    if (Math.abs(arr[idx] - h) < 0.5) {
      return;
    }
    arr[idx] = h;
    this.contentH = arr;
    const rows: number[] = [0, 0, 0, 0];
    for (let i = 0; i < 8; i++) {
      const r: number = Math.floor(i / 2);
      if (arr[i] > rows[r]) {
        rows[r] = arr[i];
      }
    }
    this.rowH = [rows[0] + 2, rows[1] + 2, rows[2] + 2, rows[3] + 2];
  }

  private gridCols(): number {
    return R.cols();
  }

  /**
   * 宽的板块占 2 列（网页端 .span2）。
   *
   * v4.26：2 列时**不再**让宽卡独占整行。
   *   原因：ArkUI 的 GridRow 不会像 CSS grid 那样自动补位 ——
   *   2 列里排 [2,1,2,1,…]，宽卡占满一行后，后面那张窄卡只能自己占半行，
   *   右边空出半行（平板竖屏下实测空了 346vp），最后一张卡还被挤到屏幕外。
   *   ⇒ 2 列时所有卡都占 1 列（两两成对），跟网页端 ≤820px 的单列效果一致，
   *   不会有空洞；3 列时仍按 .span2 走。
   */
  private spanFor(weight: number): number {
    const c: number = R.cols();
    if (weight >= 2 && c >= 3) {
      return 2;
    }
    return 1;
  }

  /** 3 列 / 2 列时都做「同行等高」（网页端 .home-grid 的 align-items:stretch） */
  private gridWide(): boolean {
    return R.cols() >= 2;
  }

  /** 宽屏用 layoutWeight 分配宽度（2:1），窄屏返回 0 表示按百分比宽度走 */
  private gw(weight: number): number {
    return this.gridWide() ? weight : 0;
  }

  /** 一行两块之间 14vp 空隙，左右各让 7 */
  private gapHalf(): number {
    return this.gridWide() ? 7 : 0;
  }

  /** 3 列时同一行的两块拉齐高度；其余模式保持各自高度 */
  @Builder skeletonBlock(w: string, h: number) {
    Row().width(w).height(h).backgroundColor(tc(this.dark, '#EAF2FA', 0)).borderRadius(13)
  }

  @Builder skeleton() {
    Column({ space: 12 }) {
      Row().width('60%').height(24).backgroundColor(tc(this.dark, '#E3EDF7', 0)).borderRadius(10)
      Row().width('45%').height(13).backgroundColor(tc(this.dark, '#EAF2FA', 0)).borderRadius(8)
      Row({ space: 8 }) {
        this.skeletonBlock('48%', 78)
        this.skeletonBlock('48%', 78)
      }.width('100%')
      this.skeletonBlock('100%', 170)
      this.skeletonBlock('100%', 140)
      this.skeletonBlock('100%', 120)
    }
    .width('100%')
    .padding({ left: S.pagePad, right: S.pagePad, top: S.pageTop })
    .alignItems(HorizontalAlign.Start)
  }

  /** .task-row 的一行 */
  @Builder taskRow(t: Task) {
    Row({ space: 10 }) {
      StatusDot({
        status: t.status,
        dotSize: 20,
        onTap: () => { this.cycleStatus(t); }
      })

      Text(areaLabel(t.area))
        .fontSize(8.5)
        .fontColor(catColor(this.dark, t.area))
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(6)
        .backgroundColor(catBg(this.dark, t.area))

      Text(t.title)
        .fontSize(S.bodySize)
        .fontColor(t.status === 'done' ? tc(this.dark, '#A3B3C1', 1) : tk(this.dark, 'text'))
        .decoration({ type: t.status === 'done' ? TextDecorationType.LineThrough : TextDecorationType.None, color: '#A3B3C1' })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(this.taskMeta(t))
        .fontSize(S.tinySize)
        .fontColor(tc(this.dark, '#A2B3C2', 1))
        .maxLines(1)
        .flexShrink(0)

      // v4.23：fs14 墨迹 11.7x10.6vp（盒子 14x14 >= 12vp、墨迹 >= 8vp）
      SymbolGlyph(sym('right')).fontSize(14).fontColor([tc(this.dark, '#C2D0DB', 1)])
    }
    .width('100%')
    .padding({ left: 8, right: 6, top: 10, bottom: 10 })
    .borderRadius(11)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onNavigate('tasks'); })
  }

  private taskMeta(t: Task): string {
    let s: string = t.due_date !== null ? D.md(t.due_date) : '长期';
    if (t.scheduled_start !== null) { s = `${s} · ${D.hm(t.scheduled_start)}`; }
    if (t.priority === 'high') { s = `${s} 要紧`; }
    return s;
  }

  /** 一条日程 */
  @Builder eventRow(e: EventItem) {
    Row({ space: 8 }) {
      Row().width(3).height(22).borderRadius(2).backgroundColor(tk(this.dark, 'event'))
      Text(e.all_day === 1 ? '全天' : D.hm(e.start_at))
        .fontSize(10)
        .fontColor(tk(this.dark, 'textSub'))
        .width(38)
      Text(e.title)
        .fontSize(S.subSize)
        .fontColor(tk(this.dark, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (e.location.length > 0) {
        Text(e.location)
          .fontSize(S.microSize)
          .fontColor(tk(this.dark, 'textHint'))
          .maxLines(1)
          .constraintSize({ maxWidth: 90 })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onNavigate('calendar'); })
  }

  /** 整周视图：本周日程 */
  @Builder weekPanel() {
    Column({ space: 7 }) {
      if (this.kWeekEvents.length > 0) {
        Text('本周日程').fontSize(10.5).fontWeight(FontWeight.Medium).fontColor(tk(this.dark, 'textSub'))
        ForEach(this.kWeekEvents, (e: EventItem) => {
          this.eventRow(e)
        }, (e: EventItem) => `we-${e.id}-${this.tick}`)
      }
      if (this.kWeekTasks.length > 0) {
        Text('已排期任务').fontSize(10.5).fontWeight(FontWeight.Medium).fontColor(tk(this.dark, 'textSub'))
          .margin({ top: 4 })
        ForEach(this.kWeekTasks, (t: Task) => {
          this.weekTaskRow(t)
        }, (t: Task) => `wk-${t.id}-${this.tick}`)
      }
      if (this.kWeekEvents.length === 0 && this.kWeekTasks.length === 0) {
        Text('本周还没有安排到具体时间的事。')
          .fontSize(S.tinySize)
          .fontColor(tc(this.dark, '#B9CAD8', 1))
          .padding({ top: 8 })
      }
      Text('点上面的日期，看那天具体有什么。')
        .fontSize(S.microSize)
        .fontColor(tk(this.dark, 'textHint'))
        .margin({ top: 6 })
    }
    .width('100%')
    .margin({ top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 排期任务一行 */
  @Builder weekTaskRow(t: Task) {
    Row({ space: 8 }) {
      StatusDot({
        status: t.status,
        dotSize: 20,
        onTap: () => { this.cycleStatus(t); }
      })
      Text(t.title)
        .fontSize(S.subSize)
        .fontColor(tk(this.dark, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(t.scheduled_start !== null ? D.hm(t.scheduled_start) : '')
        .fontSize(S.microSize)
        .fontColor(tk(this.dark, 'textHint'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 选中某一天：那天具体的安排 */
  @Builder dayPanel() {
    Column({ space: 7 }) {
      Row({ space: 6 }) {
        Text(this.dayPickLabel())
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(tk(this.dark, 'textSub'))
        Blank()
        Text('看整周')
          .fontSize(9.5)
          .fontColor(tkInk(this.dark, 'brandDeep'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor(tk(this.dark, 'brandSoft'))
          .onClick(() => { this.dayPick = -1; })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.kDayEvents.length === 0 && this.kDayTasks.length === 0) {
        Text('这天还没有安排。')
          .fontSize(S.tinySize)
          .fontColor(tc(this.dark, '#B9CAD8', 1))
          .padding({ top: 4, bottom: 4 })
      } else {
        ForEach(this.kDayEvents, (e: EventItem) => {
          this.eventRow(e)
        }, (e: EventItem) => `de-${e.id}-${this.tick}`)
        ForEach(this.kDayTasks, (t: Task) => {
          this.weekTaskRow(t)
        }, (t: Task) => `dt-${t.id}-${this.tick}`)
      }
    }
    .width('100%')
    .margin({ top: 10 })
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .borderRadius(11)
    .backgroundColor(tc(this.dark, '#F7FBFE', 0))
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F0F8', 2), 2) })
    .alignItems(HorizontalAlign.Start)
  }

  // 顶部栏（对齐工作台 TopBar 手机端：搜索 / 提醒 / 日历 + 主操作）
  @Builder pageTop() {
    TopBar({
      primaryText: '添加任务',
      onPrimary: () => { this.openSheet(); },
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  // ── 5 个 KPI（v4.6 抽成 builder，手机两列 / 平板一排 5 个）──
  @Builder kpiToday() {
    Column() {
      Kpi({
        label: '我的任务', icon: 'tasks', value: `${this.kAllTasks}`,
        unit: '项', sub: `已完成 ${this.kDoneCount} 项`, pct: this.kAllPct
      })
    }.layoutWeight(1)
  }

  @Builder kpiRate() {
    Column() {
      Kpi({
        label: '完成率', icon: 'checkCircle', iconBg: '#E3F8F2', iconFg: '#267261',
        value: `${this.kAllPct}`, unit: '%',
        sub: this.kPctSub,
        subColor: tkInk(this.dark, 'brandDeep'), pct: this.kAllPct
      })
    }.layoutWeight(1)
  }

  @Builder kpiStreak() {
    Column() {
      Kpi({
        label: '习惯打卡', icon: 'flame', iconBg: '#FDEEE6', iconFg: '#A44F26',
        value: `${this.kHabitStreak}`, unit: '天', sub: this.kHabitSub,
        pct: this.kHabitPct
      })
    }.layoutWeight(1)
  }

  @Builder kpiFocus() {
    Column() {
      Kpi({
        label: '专注时长', icon: 'clock', iconBg: '#E9F3FB', iconFg: '#356B91',
        value: this.kFocusH, unit: '小时', sub: '每天目标 2 小时 · 按预估算',
        pct: this.kFocusPct
      })
    }.layoutWeight(1)
  }

  @Builder kpiPoints() {
    Column() {
      Kpi({
        label: '成长积分', icon: 'star', iconBg: '#FDF4DC', iconFg: '#876312',
        value: `${this.kPoints}`, unit: '分', sub: `本周 ${this.kWeekPoints} / 30 分`,
        pct: this.kPointsPct
      })
    }.layoutWeight(1)
  }

  build() {
    Stack() {

      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          if (!this.loaded) {
            this.skeleton()
          } else {
            Column({ space: 0 }) {
              Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

              this.pageTop()

              // ① hello：eyebrow + h1 + 副文案（v4.2：右上角显示设置里的「称呼」）
              Column({ space: 6 }) {
                Row({ space: 6 }) {
                  Text(`${D.dotDate(new Date())} · ${D.weekdayFull(new Date())}`)
                    .fontSize(9)
                    .fontColor(tc(this.dark, '#9DB0C1', 1))
                    .letterSpacing(1.6)
                  Blank()
                  if (this.kUserName.length > 0) {
                    Row({ space: 4 }) {
                      SymbolGlyph(sym('person')).fontSize(14).fontColor([tkInk(this.dark, 'brandDeep')])
                      Text(this.kUserName)
                        .fontSize(9.5)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(tkInk(this.dark, 'brandDeep'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .padding({ left: 8, right: 9, top: 3, bottom: 3 })
                    .borderRadius(999)
                    .backgroundColor(tk(this.dark, 'brandSoft'))
                    .alignItems(VerticalAlign.Center)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                Text(this.kHeaderTitle)
                  .fontSize(S.titleSize)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(tk(this.dark, 'text'))
                  .letterSpacing(-0.6)
                  .lineHeight(32)
                Text(this.kHeaderSub)
                  .fontSize(11)
                  .fontColor(tk(this.dark, 'textSub'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ top: 14, bottom: 16 })

              // v3.0：全部内容入口（任务 / 灵感 / 日程 / 项目 / 复盘 / 习惯，一处看全）
              Row({ space: 6 }) {
                SymbolGlyph(sym('grid')).fontSize(14).fontColor([tkInk(this.dark, 'brandDeep')])
                Text('全部内容').fontSize(10.5).fontWeight(FontWeight.Medium).fontColor(tkInk(this.dark, 'brandDeep'))
                Text('所有东西，一处看全').fontSize(9.5).fontColor(tk(this.dark, 'textHint'))
                // v4.23：fs14 墨迹 11.7x10.6vp（盒子 14x14 >= 12vp、墨迹 >= 8vp）
                SymbolGlyph(sym('right')).fontSize(14).fontColor([tk(this.dark, 'textHint')])
              }
              .padding({ left: 11, right: 11, top: 7, bottom: 7 })
              .margin({ bottom: 14 })
              .borderRadius(999)
              .backgroundColor(tk(this.dark, 'brandSoft'))
              .border({ width: 1, color: tk(this.dark, 'brandLine') })
              .alignItems(VerticalAlign.Center)
              .onClick(() => { this.onNavigate('all'); })

              // ② 5 个 KPI（手机端两列、第 5 个占满；平板一行 5 个，照网页端 .kpis）
              // v4.26：中间档（平板竖屏，导航收成 70vp 之后内容区约 858vp）走 3 + 2，
              //   和网页端 @media(max-width:1180px) 的 .kpis{repeat(3,1fr)} 对齐，
              //   两张卡各占半行（layoutWeight 分的是整行宽度），不会留空洞。
              if (this.contentW >= 900) {
                Row({ space: 8 }) {
                  this.kpiToday()
                  this.kpiRate()
                  this.kpiStreak()
                  this.kpiFocus()
                  this.kpiPoints()
                }
                .width('100%')
              } else if (this.contentW >= 620) {
                Row({ space: 8 }) {
                  this.kpiToday()
                  this.kpiRate()
                  this.kpiStreak()
                }
                .width('100%')

                Row({ space: 8 }) {
                  this.kpiFocus()
                  this.kpiPoints()
                }
                .width('100%')
                .margin({ top: 8 })
              } else {
                Row({ space: 8 }) {
                  this.kpiToday()
                  this.kpiRate()
                }
                .width('100%')

                Row({ space: 8 }) {
                  this.kpiStreak()
                  this.kpiFocus()
                }
                .width('100%')
                .margin({ top: 8 })

                Row({ space: 8 }) {
                  this.kpiPoints()
                }
                .width('100%')
                .margin({ top: 8 })
              }

              // v4.12：说清楚「习惯打卡」是什么；上下都留出间距，别贴着下面的卡
              Text('「习惯打卡」= 现在还连着的最长天数（今天还没打卡不打断）；历史最长写在副标题里')
                .fontSize(9)
                .fontColor(tk(this.dark, 'textFaint'))
                .width('100%')
                .margin({ top: 10, bottom: 14 })

              // v4.6：宽屏时 ③–⑩ 照网页端 .home-grid 排版：
              // 一行两块 —— 宽的（趋势 / 最近任务 / 核心模块 / 灵感派）占 2 列，
              // 窄的（投入占比 / 成长日历 / 本周小结 / 今日一句）占 1 列；
              // 同一行的两块拉齐高度，不留参差不齐的空当（手机上仍是单列顺序排）。
              Column() {
              GridRow({ columns: this.gridCols(), gutter: { x: 14, y: 14 } }) {
              // ③ 本周成长趋势
              GridCol({ span: this.spanFor(2) }) {
                Column() {
                  Card({
                      fixedHeight: this.gridWide() ? this.rowH[0] : 0,
                      onContentHeight: (h: number) => { this.setContentH(0, h); },
                      title: '本周成长趋势', sub: '每天专注时长',
                    headMode: this.trendRange === 0 ? 'text' : 'text',
                    headText: this.trendRange === 0 ? '上周 ›' : '本周 ›',
                    onHead: () => { this.trendRange = this.trendRange === 0 ? 1 : 0; this.recalc(); }
                  }) {
                    Column({ space: 2 }) {
                      Row({ space: 6 }) {
                        Text(`${this.kTrendSum}h`).fontSize(22).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text'))
                        Text(this.trendRange === 1 ? '上周累计专注' : '本周累计专注').fontSize(S.tinySize).fontColor(tk(this.dark, 'textFaint'))
                        Blank()
                      }
                      .width('100%')
                      .alignItems(VerticalAlign.Bottom)
                      LineChart({ values: this.kTrendValues, labels: this.kTrendLabels, chartHeight: 150,
                      onBubble: (bx: number, by: number, bw: number, bh: number) => { this.bubbleLocal = [bx, by, bw, bh]; } })
                    .onAreaChange((oldA: Area, newA: Area) => { this.chartArea(oldA, newA); })
                      Row({ space: 10 }) {
                        Row({ space: 4 }) {
                          Row().width(6).height(6).borderRadius(3).backgroundColor(tk(this.dark, 'brand'))
                          Text('专注时长（小时）').fontSize(S.microSize + 0.5).fontColor(tk(this.dark, 'textHint'))
                        }
                        Text('按任务完成日统计').fontSize(S.microSize + 0.5).fontColor(tk(this.dark, 'textHint'))
                      }
                      .width('100%')
                      .margin({ top: 4 })
                    }
                    .width('100%')
                  }

                }
              }

              // ④ 模块投入占比
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  Card({
                      fixedHeight: this.gridWide() ? this.rowH[0] : 0,
                      onContentHeight: (h: number) => { this.setContentH(1, h); },
                      title: '模块投入占比',
                    headMode: 'text',
                    headText: this.investRange === 0 ? '本月 ›' : '本周 ›',
                    onHead: () => { this.investRange = this.investRange === 0 ? 1 : 0; this.recalc(); }
                  }) {
                    Column({ space: 10 }) {
                      Column() {
                        Donut({ pieces: this.kInvestPieces, centerBig: this.kInvestTotal, centerSmall: this.investRange === 1 ? '本月总投入' : '本周总投入' })
                      }
                      .width('100%')
                      .alignItems(HorizontalAlign.Center)

                      DonutLegend({ pieces: this.kInvestPieces })

                      Divider().color('#EAF2F9').strokeWidth(1).margin({ top: 2 })

                      Row({ space: 3 }) {
                        ForEach(this.kInvestItems, (i: InvestItem) => {
                          Row()
                            .layoutWeight(Math.max(i.pct, 2))
                            .height(5)
                            .backgroundColor(i.hex)
                        }, (i: InvestItem) => `dfb-${i.area}`)
                      }
                      .width('100%')
                      .height(5)
                      .borderRadius(99)

                      Text(this.kInvestItems.length > 0 && this.kInvestItems[0].pct > 0
                        ? `这周你在 ${this.kInvestItems[0].label} 上花的时间最多，占 ${this.kInvestItems[0].pct}%。`
                        : '本周还没有排期，先给一件事留个时间块。')
                        .fontSize(S.subSize)
                        .fontColor(tc(this.dark, '#6E8497', 1))
                        .lineHeight(18)
                        .width('100%')
                    }
                    .width('100%')
                  }

                }
              }


              // ⑤ 最近任务
              GridCol({ span: this.spanFor(2) }) {
                Column() {
                  Card({
                    fixedHeight: this.gridWide() ? this.rowH[1] : 0,
                      onContentHeight: (h: number) => { this.setContentH(2, h); },
                    title: '最近任务', headMode: 'text', headText: '查看全部 ›', onHead: () => { this.onNavigate('tasks'); } }) {
                    Column({ space: 2 }) {
                      if (this.kRecentCount === 0) {
                        Column({ space: 5 }) {
                          // v4.4：一条任务都没有 vs 全部做完了，是两回事，别都写「还没有任务」
                          Text(this.kTotalTasks === 0 ? '还没有任务' : '都做完了')
                            .fontSize(S.bodySize).fontWeight(FontWeight.Medium).fontColor(tk(this.dark, 'textFaint'))
                          Text(this.kTotalTasks === 0 ? '先加一件今天想做的事。' : '所有任务都完成了，休息一下。')
                            .fontSize(S.subSize).fontColor(tk(this.dark, 'textPale'))
                        }
                        .width('100%')
                        .padding({ top: 18, bottom: 18 })
                        .alignItems(HorizontalAlign.Center)
                      } else {
                        ForEach(this.kRecent, (t: Task) => {
                          this.taskRow(t)
                        }, (t: Task) => `rc-${t.id}-${this.tick}`)
                      }

                      Divider().color('#EAF2F9').strokeWidth(1).margin({ top: 8 })

                      Row({ space: 6 }) {
                        Text(`还有 ${this.kOpenAll} 件待处理`).fontSize(10).fontColor(tk(this.dark, 'textFaint'))
                        Blank()
                        Text('去任务面板 →')
                          .fontSize(10)
                          .fontColor(tc(this.dark, '#5E7183', 1))
                          .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                          .borderRadius(9)
                          .backgroundColor(tk(this.dark, 'card'))
                          .border({ width: 1, color: tk(this.dark, 'line') })
                          .onClick(() => { this.onNavigate('tasks'); })
                      }
                      .width('100%')
                      .margin({ top: 8 })
                      .alignItems(VerticalAlign.Center)
                    }
                    .width('100%')
                  }

                }
              }

              // ⑥ 本月成长日历
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  Card({
                      fixedHeight: this.gridWide() ? this.rowH[1] : 0,
                      onContentHeight: (h: number) => { this.setContentH(3, h); },
                      title: '本月成长日历', headMode: 'arrows',
                    onPrev: () => { this.calOffset -= 1; this.recalc(); },
                    onNext: () => { this.calOffset += 1; this.recalc(); }
                  }) {
                    MonthCal({ cells: this.kCalCells, monthLabel: this.kCalLabel, doneCount: this.kCalDone })
                  }

                }
              }


              // ⑦ 核心模块
              GridCol({ span: this.spanFor(2) }) {
                Column() {
                  Card({
                    fixedHeight: this.gridWide() ? this.rowH[2] : 0,
                      onContentHeight: (h: number) => { this.setContentH(4, h); },
                    title: '核心模块', headMode: 'text', headText: '进入任务面板 ›', onHead: () => { this.onNavigate('tasks'); } }) {
                    Column({ space: 8 }) {
                      Row({ space: 8 }) {
                        Column() {
                          ModTile({ icon: 'tasks', label: '任务面板', sub: '计划与打卡', onTap: () => { this.onNavigate('tasks'); } })
                        }.layoutWeight(1)
                        Column() {
                          ModTile({
                            icon: 'calendar', label: '日历安排', sub: '日程与时间块',
                            iconBg: '#E3F8F2', iconFg: '#267261', onTap: () => { this.onNavigate('calendar'); }
                          })
                        }.layoutWeight(1)
                      }.width('100%')
                      Row({ space: 8 }) {
                        Column() {
                          ModTile({
                            icon: 'note', label: '记录灵感', sub: '随手写下想法',
                            iconBg: '#FCEAF2', iconFg: '#AA4071', onTap: () => { this.onNavigate('notes'); }
                          })
                        }.layoutWeight(1)
                        Column() {
                          ModTile({
                            icon: 'wand', label: '每日复盘', sub: '回顾与调整',
                            iconBg: '#F1ECFE', iconFg: '#6B4FD0', onTap: () => { this.onNavigate('review'); }
                          })
                        }.layoutWeight(1)
                      }.width('100%')
                      Row({ space: 8 }) {
                        Column() {
                          ModTile({
                            icon: 'target', label: '每日习惯', sub: '连续打卡',
                            iconBg: '#FDF4DC', iconFg: '#876312', onTap: () => { this.onNavigate('habits'); }
                          })
                        }.layoutWeight(1)
                        Column() {
                          ModTile({
                            icon: 'grid', label: '数据洞察', sub: '趋势与投入',
                            iconBg: '#E9F3FB', iconFg: '#356B91', onTap: () => { this.onNavigate('stats'); }
                          })
                        }.layoutWeight(1)
                      }.width('100%')
                      Row({ space: 8 }) {
                        Column() {
                          ModTile({
                            icon: 'search', label: '全局搜索', sub: '找任何一条',
                            iconBg: '#E1F7F5', iconFg: '#0F6B66', onTap: () => { this.onNavigate('search'); }
                          })
                        }.layoutWeight(1)
                        Column() {
                          ModTile({
                            icon: 'gear', label: '偏好设置', sub: '本地与 AI',
                            iconBg: '#F0F4F8', iconFg: '#52697E', onTap: () => { this.onNavigate('settings'); }
                          })
                        }.layoutWeight(1)
                      }.width('100%')
                    }
                    .width('100%')
                  }

                }
              }

              // ⑧ 本周小结
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  Card({
                    fixedHeight: this.gridWide() ? this.rowH[2] : 0,
                      onContentHeight: (h: number) => { this.setContentH(5, h); },
                    title: '本周小结' }) {
                    Column({ space: 10 }) {
                      Text(this.kSummary)
                        .fontSize(S.subSize)
                        .fontColor(tc(this.dark, '#4E6579', 1))
                        .lineHeight(19)
                        .width('100%')
                      MiniBars({ values: this.kTrendValues, chartHeight: 44 })
                    }
                    .width('100%')
                  }

                }
              }


              // ⑨ 灵感派
              GridCol({ span: this.spanFor(2) }) {
                Column() {
                  Card({
                      fixedHeight: this.gridWide() ? this.rowH[3] : 0,
                      onContentHeight: (h: number) => { this.setContentH(6, h); },
                      title: '灵感派', sub: '从记录里挑',
                    headMode: 'text', headText: '换一批 ›',
                    onHead: () => { this.spin += 1; this.recalc(); }
                  }) {
                    Column({ space: 10 }) {
                      if (this.kCandCount === 0) {
                        Column({ space: 5 }) {
                          Text('还没有记录').fontSize(S.bodySize).fontColor(tk(this.dark, 'textFaint'))
                          Text('随手记下第一条灵感。').fontSize(S.subSize).fontColor(tk(this.dark, 'textPale'))
                        }
                        .width('100%')
                        .padding({ top: 14, bottom: 14 })
                        .alignItems(HorizontalAlign.Center)
                      } else {
                        Column() {
                          Donut({ pieces: this.kCandPieces, boxSize: 118, holeSize: 22 })
                        }
                        .width(118)
                        .height(118)
                        .borderRadius(59)
                        .backgroundColor(tk(this.dark, 'card'))
                        .justifyContent(FlexAlign.Center)
                        .onClick(() => { this.spin += 1; })

                        Column({ space: 2 }) {
                          ForEach(this.kCandItems.slice(0, 3), (c: CandItem, idx: number) => {
                            Column({ space: 4 }) {
                              Row({ space: 8 }) {
                                Row() {
                                  Text(`${idx + 1}`).fontSize(8).fontColor(idx === 0 ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#8FA2B3', 1))
                                }
                                .width(16)
                                .height(16)
                                .borderRadius(8)
                                .backgroundColor(idx === 0 ? tk(this.dark, 'brandSoft') : tc(this.dark, '#F1F7FC', 0))
                                .justifyContent(FlexAlign.Center)
                                .alignItems(VerticalAlign.Center)
                                Text(c.title)
                                  .fontSize(S.subSize)
                                  .fontColor(tk(this.dark, 'text'))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                                  .layoutWeight(1)
                                Text(`${c.pct}%`).fontSize(S.microSize).fontColor(tc(this.dark, '#8FA2B3', 1))
                              }
                              .width('100%')
                              .padding({ top: 5, bottom: 3 })
                              .alignItems(VerticalAlign.Center)

                              Row() {
                                Row()
                                  .width(`${c.pct}%`)
                                  .height(4)
                                  .borderRadius(2)
                                  .backgroundColor(c.color)
                              }
                              .width('100%')
                              .height(4)
                              .borderRadius(2)
                              .backgroundColor(tk(this.dark, 'track'))
                            }
                            .width('100%')
                            .onClick(() => { this.onNavigate('notes'); })
                          }, (c: CandItem) => `cand-${c.id}-${c.pct}-${this.tick}`)

                          Text('从记下的东西里，挑一条现在就动手。')
                            .fontSize(S.microSize + 0.5)
                            .fontColor(tk(this.dark, 'textHint'))
                            .margin({ top: 6 })
                        }
                        .width('100%')
                      }
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Center)
                  }

                }
              }

              // ⑩ 今日一句
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  Card({
                    fixedHeight: this.gridWide() ? this.rowH[3] : 0,
                      onContentHeight: (h: number) => { this.setContentH(7, h); },
                    title: '今日一句', headMode: 'text', headText: '全部 ›', onHead: () => { this.onNavigate('notes'); } }) {
                    Column({ space: 9 }) {
                      Row({ space: 8 }) {
                        SymbolGlyph(sym('quote')).fontSize(14).fontColor([tc(this.dark, '#B9CAD8', 1)])
                        Column({ space: 4 }) {
                          Text('每一个微小的坚持，都在让你靠近更喜欢的自己。')
                            .fontSize(S.bodySize)
                            .fontColor(tc(this.dark, '#4E6579', 1))
                            .lineHeight(21)
                            .width('100%')
                          if (this.kQuote.length > 0) {
                            Text(`最近记下：${this.kQuote}`)
                              .fontSize(S.tinySize)
                              .fontColor(tk(this.dark, 'textHint'))
                              .width('100%')
                          }
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                      }
                      .width('100%')
                      .alignItems(VerticalAlign.Top)

                      if (this.notes.length > 0) {
                        Column({ space: 6 }) {
                          ForEach(this.notes.slice(0, 3), (n: Note) => {
                            Row({ space: 7 }) {
                              Row().width(6).height(6).borderRadius(3).backgroundColor(tk(this.dark, 'brand'))
                              Text(n.title.length > 0 ? n.title : n.content.substring(0, 16))
                                .fontSize(S.subSize)
                                .fontColor(tc(this.dark, '#4E6579', 1))
                                .maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                .layoutWeight(1)
                              Text(D.short(D.dateOf(n.updated_at))).fontSize(S.microSize).fontColor(tk(this.dark, 'textHint'))
                            }
                            .width('100%')
                            .alignItems(VerticalAlign.Center)
                            .onClick(() => { this.onNavigate('notes'); })
                          }, (n: Note) => `qn-${n.id}-${this.tick}`)
                        }
                        .width('100%')
                      }

                      Divider().color('#EAF2F9').strokeWidth(1)
                      Row({ space: 6 }) {
                        Text('共 ').fontSize(10).fontColor(tk(this.dark, 'textFaint'))
                        Text(`${this.notes.length}`).fontSize(10).fontColor(tc(this.dark, '#4E6579', 1)).fontWeight(FontWeight.Medium)
                        Text(' 条记录').fontSize(10).fontColor(tk(this.dark, 'textFaint'))
                        Blank()
                      }
                      .width('100%')
                    }
                    .width('100%')
                  }

                }
              }
              }
              .alignItems(ItemAlign.Start)
              .width('100%')
              }
              .width('100%')

              // ⑪ 本周安排（v2.9：接入日历日程；日期可点，看那天的安排）
              SecHead({
                title: '本周安排', count: `${this.kWeekArrCount} 件安排`, rightMode: 'arrows',
                onPrev: () => { this.weekOffset -= 1; this.dayPick = -1; this.recalc(); },
                onNext: () => { this.weekOffset += 1; this.dayPick = -1; this.recalc(); }
              })

              Column() {
                Card({ title: '给灵感留一点时间', sub: this.kWeekRange }) {
                  WeekGantt({
                    dayNums: this.kWeekDayNums,
                    todayIdx: this.kTodayIdx,
                    bars: this.kWeekBars,
                    selectedIdx: this.dayPick,
                    onDayTap: (i: number) => {
                this.dayPick = this.dayPick === i ? -1 : i;
                this.recalc();
              }
                  })

                  if (this.dayPick >= 0) {
                    this.dayPanel()
                  } else {
                    this.weekPanel()
                  }

                  Row({ space: 10 }) {
                    ForEach(['work', 'side', 'media', 'study', 'life'], (a: string) => {
                      Row({ space: 4 }) {
                        Row().width(6).height(6).borderRadius(2).backgroundColor(areaColor(this.dark, a))
                        Text(areaLabel(a)).fontSize(S.microSize).fontColor(tk(this.dark, 'textHint'))
                      }
                    }, (a: string) => `wf-${a}`)
                  }
                  .width('100%')
                  .margin({ top: 8 })
                }
              }
              .width('100%')
              .margin({ bottom: S.pageBottom })
            }
            .width('100%')
            .padding({ left: S.pagePad, right: S.pagePad, top: S.pageTop })
            .alignItems(HorizontalAlign.Start)
          }
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
        // v4.5：滚动时把右下角悬浮按钮藏起来（它正好压在趋势图末点气泡上），停了就回来
        .onDidScroll(() => { AppStorage.setOrCreate<boolean>('wb_scrolling', true); })
        .onScrollStop(() => { AppStorage.setOrCreate<boolean>('wb_scrolling', false); })
      }
      .onRefreshing(() => { this.doRefresh(); })
      .width('100%')
      .height('100%')
      .bindSheet($$this.showAdd, this.addSheet(), {
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
        this.addSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder addSheetBody() {
    TaskSheet({
      editingId: -1,
      defaultStatus: 'todo',
      onSaved: () => {
        this.closeSheet();
        toast(this.getUIContext(), '任务已添加');
      },
      onCancel: () => { this.closeSheet(); }
    })
  }

  /** v4.6：宽屏（平板/折叠屏）走「遮罩 + 居中卡片」，窄屏还是底部抽屉 */
  @Builder addSheet() {
    SheetFrame({
      wide: this.wideMode(),
      onClose: () => { this.closeSheet(); },
      content: () => { this.addSheetBody(); }
    })
  }

  private candPieces(): RingPiece[] {
    const out: RingPiece[] = [];
    for (const c of this.candidates()) { out.push(ringPiece(c.title, c.pct, c.color, c.pct)); }
    return out;
  }
}
