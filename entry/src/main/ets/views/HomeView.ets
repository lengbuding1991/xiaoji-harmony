// 成长总览（首页）
// 结构逐块对齐「个人工作台」components/Dashboard.tsx：hello → 5 个 KPI → 趋势 → 投入 → 最近任务
// → 月历 → 核心模块 → 本周小结 → 灵感派 → 今日一句 → 本周安排（任务+日程，日历条可点）。
// v2.9：底部「任务看板」整块已删（和任务面板重复，用户要求）。
// v3.0：hello 下面加了一颗「所有内容」胶囊 → 跳 AllView（任务/记录/日程/项目/复盘/习惯 一处看全）。
// 手机上全部单列竖排（工作台在 <=820px 时 .home-grid 也是单列）。
import { Store, isConsumedRepeat, isOverdue, overdueDays } from '../store/Store';
import { areaColor, areaLabel, barBg, barColor, brandGradient, catBg, catColor, misc, onFill, paletteAt, paletteList, S, tc, tk, tkInk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { toast } from '../utils/Toast';
import { Card } from '../components/Card';
import { Donut, DonutLegend, ringPiece, RingPiece } from '../components/Donut';
import { Kpi, SecHead, WeekGantt, GanttBar, ganttBar } from '../components/Widgets';
import { R } from '../utils/Responsive';
import { IconBox } from '../components/IconBox';
import { sym } from '../components/Icon';
import { Task, Note, TaskCreate, TaskStatus, EventItem, HabitView } from '../api/Types';
import { StatusDot } from '../components/StatusDot';
import { TopBar } from '../components/TopBar';
import { TaskSheet } from '../components/TaskSheet';
import { SheetFrame } from '../components/SheetFrame';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

/** v5.12：首页「接下来」卡里的一行（一条日程） */
interface NextEvent {
  id: number;
  startAt: string;
  dayKey: string;
  isToday: boolean;
  dayLabel: string;
  timeLabel: string;
  title: string;
}

interface InvestItem {
  area: string;
  label: string;
  hex: string;
  v: number;
  pct: number;
}

/**
 * v5.5：周明细里的一天。
 * v5.4 是「每天最多 3 条标题」，结果同一天的数据在「整周」和「点开某天」两种
 * 画法里长得不一样（一边标题、一边带时间），用户看着别扭。
 * v5.5 改成：**整周只报数**（几条任务 / 几条日程），点开某天才看明细。
 */
interface WeekGroup {
  idx: number;
  label: string;
  dateText: string;
  taskCount: number;
  eventCount: number;
  isToday: boolean;
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
  @StorageLink('wb_pal') pal: number = 0;
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
  // v5.14：整库读取失败的原因（「读不出来」要和「本来没数据」分开说）
  @State kLoadError: string = '';
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

  @State investRange: number = 0;    // 0=本周 1=本月
  @State weekOffset: number = 0;
  @State spin: number = 0;
  // v4.6：宽屏档位（0 手机 / 1 小平板 / 2 平板）。变了这一页要重画
  @StorageLink('wb_layout') layoutMode: number = 0;
  // v4.6：内容区宽度（扣掉左侧导航后的实际宽度），决定 KPI 排几列
  @StorageLink('wb_content_w') contentW: number = 0;
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
  @State kPctSubShort: string = '';    // 完成率副文案（窄卡片用，短）
  @State kDueTodayOpen: number = 0;   // 今日到期且未完成（页头 N）
  // v5.1：首页第一屏的主角 —— 今日清单
  @State kTodayList: Task[] = [];      // 逾期 → 今天到期 → 往后的，最多 5 条
  @State kTodayRest: number = 0;       // 今天要做的里没显示出来的件数
  @State kSoonCount: number = 0;        // v5.13：到期日在今天之后、排期靠后的件数
  @State kTodayDoneCount: number = 0;  // 今天完成的件数
  @State undoTaskId: number = -1;      // 刚完成、可撤销的任务 id
  @State kHasHabits: boolean = false;  // v5.1：有习惯才显示习惯相关的块
  @State kAllEmpty: boolean = true;    // v5.1：整个库是空的 ⇒ 收起 KPI 区
  @State kHeaderTitle: string = '';   // 页头标题
  @State kHeaderSub: string = '';     // 页头副文案
  @State kHabitStreak: number = 0;    // 各习惯里最长的连续打卡天数
  @State kHabitPending: number = 0;   // 今天还没打卡的习惯数
  @State kHabitSub: string = '';
  @State kHabitSubShort: string = '';   // 习惯副文案（窄卡片用，短）
  @State kHabitPct: number = 0;
  @State kHabitBest: number = 0;    // 历史最长连续打卡天数
  @State kDoneAll: number = 0;        // 累计完成
  @State kOpenAll: number = 0;        // 未完成总数
  @State kWeekDone: number = 0;       // 本周完成
  // v5.12：首页下面两张卡换成「接下来」+「今天该打卡」
  @State kNextEvents: NextEvent[] = [];   // 未来 7 天的日程（最多 4 条）
  @State kNextMore: number = 0;            // 超出 4 条的还剩几条
  @State kNextOverdue: number = 0;         // 已经逾期的任务数
  @State kHabitRows: HabitView[] = [];     // 习惯行（最多 3 个）
  @State kHabitDays: string[] = [];        // 最近 7 天（今天在最后）
  @State kHabitToday: string = '';
  @State kHabitPending2: number = 0;       // 今天还没打卡的习惯数
  @State kInvestItems: InvestItem[] = [];
  @State kInvestPieces: RingPiece[] = [];
  @State kInvestTotal: string = '0.0';
  @State kSummary: string = '';
  @State kQuote: string = '';
  @State kRecentCount: number = 0;
  // v5.1：首页那张「随手记」卡可以就地展开最近记的几条，不用跳页
  @State notesOpen: boolean = false;
  @State kCandItems: CandItem[] = [];
  @State kCandPieces: RingPiece[] = [];
  @State kCandCount: number = 0;
  @State kWeekArrCount: number = 0;
  @State kWeekDayNums: string[] = [];
  // v5.4：按天分组的周明细（每天最多 3 条标题）
  @State kWeekGroups: WeekGroup[] = [];
  @State kWeekBars: GanttBar[] = [];
  @State kWeekRange: string = '';
  // v5.0：上次上报的滚动偏移（背景光斑视差，超过 10px 才上报）
  private lastScrollY: number = 0;
  private undoTimer: number = -1;
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
    this.kLoadError = Store.I.loadError;
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
    // v5.15：总数与完成率改用 Store 的唯一实现（以前这一页自己算一遍、任务面板又算一遍）
    this.kAllTasks = Store.I.totalTaskCount();
    this.kDoneCount = doneAll.length;
    this.kOpenCount = open.length;
    this.kAllPct = Store.I.completedRate();
    this.kPctSub = this.kAllTasks === 0
      ? '还没有任务'
      : (this.kOpenCount > 0 ? `还剩 ${this.kOpenCount} 件没做完` : '全部做完了');
    // v5.16：窄卡片（手机三列）用的短文案 —— 长文案放不下，会被截成省略号
    this.kPctSubShort = this.kAllTasks === 0
      ? '还没有任务'
      : (this.kOpenCount > 0 ? `还剩 ${this.kOpenCount} 件` : '全部做完了');

    // 页头 N：今日到期且还没做完的件数
    const todayKey: string = D.key(new Date());
    let dueOpen: number = 0;
    for (const t of open) {
      if (t.due_date !== null && D.dateOf(t.due_date) === todayKey) { dueOpen += 1; }
    }
    this.kDueTodayOpen = dueOpen;

    // ── v5.1：今日清单 ──
    // 排序：逾期（最久的在前）→ 今天到期 → 往后的按到期时间；最多列 5 条。
    const overdue: Task[] = [];
    const dueToday: Task[] = [];
    const soon: Task[] = [];
    for (const t of open) {
      if (t.due_date === null) { continue; }
      if (isOverdue(t)) { overdue.push(t); continue; }
      const dk: string = D.dateOf(t.due_date);
      if (dk === todayKey) { dueToday.push(t); }
      else { soon.push(t); }
    }
    overdue.sort(this.cmpDue);
    dueToday.sort(this.cmpDue);
    soon.sort(this.cmpDue);
    // v5.13：口径修正。
    //   以前 allToday = 逾期 + 今天到期 + 往后的全部（往后没有时间上限），
    //   副标题拿这个集合去算「N 件事」⇒ 标题写「今天要做的」却报出所有带到期日的未完成任务
    //   （今天只有 2 件事，首页写 17 件事）。
    //   现在分成两堆：
    //     kTodayList / kTodayRest = 逾期 + 今天到期   —— 这才是「今天要做的」
    //     kSoonCount              = 到期日在今天之后的 —— 单独一行说「排在后面」
    const todayItems: Task[] = overdue.concat(dueToday);
    // v5.4：原来列 5 条。用户要「只显示 3 条，多的给一个『更多』跳任务列表」。
    this.kTodayList = todayItems.slice(0, 3);
    this.kTodayRest = Math.max(0, todayItems.length - 3);
    this.kSoonCount = soon.length;
    let doneToday: number = 0;
    for (const t of this.tasks) {
      if (t.status === 'done' && t.done_at !== null && D.dateOf(t.done_at) === todayKey) { doneToday += 1; }
    }
    this.kTodayDoneCount = doneToday;
    this.kHasHabits = this.habits.length > 0;
    this.kAllEmpty = this.tasks.length === 0 && this.notes.length === 0
      && this.events.length === 0 && this.habits.length === 0;

    // 页头 N：今天到期 + 已逾期（清单里已经装着逾期的，头部不能说「今天没有到期的事」）
    const pendingCount: number = dueOpen + overdue.length;
    this.kHeaderTitle = pendingCount > 0 ? `有 ${pendingCount} 件事要处理。` : '今天没有到期的事。';
    this.kHeaderSub = pendingCount > 0
      ? '其余都是加分项，慢慢来。'
      : '想记点什么，去「随手记」写一条。';

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
    // v5.16：窄卡片用的短文案（「今天都打卡了」这句话在下面的「今天该打卡」卡里已经说过）
    this.kHabitSubShort = this.habits.length === 0
      ? '还没有习惯'
      : (pending > 0 ? `还剩 ${pending} 个没打卡`
        : (maxBest > 0 ? `历史最长 ${maxBest} 天` : '今天都打卡了'));
    this.kHabitBest = maxBest;
    this.kHabitPct = Math.min(100, Math.round(maxStreak / 7 * 100));

    this.kDoneAll = doneAll.length;
    this.kOpenAll = open.length;

    this.kWeekDone = this.weekDone().length;
    // v4.4：归档的记录不该再计分（Store.I.notes 是含归档的）
    this.kActiveNotes = this.activeNotes().length;

    const inv: InvestItem[] = this.invest();
    this.kInvestItems = inv;
    const pieces: RingPiece[] = [];
    for (const i of inv) { pieces.push(ringPiece(i.label, i.v, i.hex, i.pct)); }
    this.kInvestPieces = pieces;
    let tot: number = 0;
    for (const i of inv) { tot += i.v; }
    this.kInvestTotal = tot.toFixed(1);


    // ── v5.12：卡 A「接下来」—— 未来 7 天的日程 + 逾期提醒 ──
    const todayK2: string = D.key(new Date());
    let overdueN: number = 0;
    for (const t of open) {
      if (isOverdue(t)) { overdueN += 1; }
    }
    this.kNextOverdue = overdueN;
    const win: string[] = [];
    for (let i = 0; i < 7; i++) { win.push(D.addDays(todayK2, i)); }
    const evs: NextEvent[] = [];
    for (const e of this.events) {
      if (e.start_at.length < 10) { continue; }
      const dk: string = e.start_at.substring(0, 10);
      if (win.indexOf(dk) < 0) { continue; }
      evs.push({
        id: e.id,
        startAt: e.start_at,
        dayKey: dk,
        isToday: dk === todayK2,
        dayLabel: this.dayTagOf(dk, todayK2),
        timeLabel: e.all_day === 1 ? '全天' : D.hm(e.start_at),
        title: e.title
      });
    }
    evs.sort((a: NextEvent, b: NextEvent) => {
      return a.startAt === b.startAt ? a.id - b.id : (a.startAt < b.startAt ? -1 : 1);
    });
    this.kNextMore = evs.length > 4 ? evs.length - 4 : 0;
    this.kNextEvents = evs.length > 4 ? evs.slice(0, 4) : evs;

    // ── v5.12：卡 B「今天该打卡」──
    this.kHabitDays = D.lastDays(7);
    this.kHabitToday = D.today();
    const alive2: HabitView[] = [];
    let pend2: number = 0;
    for (const h of this.habits) {
      if (h.archived !== 0) { continue; }
      alive2.push(h);
      if (!h.doneToday) { pend2 += 1; }
    }
    this.kHabitRows = alive2.length > 3 ? alive2.slice(0, 3) : alive2;
    this.kHabitPending2 = pend2;
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
    this.kWeekGroups = this.weekGroups();
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
    // v5.15：口径交给 Store 的唯一实现（v4.12：重复任务做完的「原件」不计入统计）
    return Store.I.doneTaskList();
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

  /** v5.5：按天统计（只报数，不列标题 —— 明细留给「点开某天」） */
  private weekGroups(): WeekGroup[] {
    const ws: Date = D.dateAdd(D.parse(D.weekStart()), this.weekOffset * 7);
    const tCount: number[] = [0, 0, 0, 0, 0, 0, 0];
    const eCount: number[] = [0, 0, 0, 0, 0, 0, 0];
    const bump = (arr: number[], when: string): void => {
      const idx: number = D.diffDays(D.parse(when), ws);
      if (idx < 0 || idx > 6) { return; }
      arr[idx] = arr[idx] + 1;
    };
    for (const t of this.weekTasks()) { bump(tCount, t.scheduled_start as string); }
    for (const e of this.weekEvents()) { bump(eCount, e.start_at); }
    const names: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const out: WeekGroup[] = [];
    for (let i = 0; i < 7; i++) {
      if (tCount[i] === 0 && eCount[i] === 0) { continue; }
      out.push({
        idx: i,
        label: names[i],
        dateText: D.md(D.key(D.dateAdd(ws, i))),
        taskCount: tCount[i],
        eventCount: eCount[i],
        isToday: i === this.todayIdxInWeek()
      });
    }
    return out;
  }

  /** v5.5/v5.15：某天的条数怎么写（3 件任务 / 2 个日程 / 3 件任务 · 1 个日程）
   *  v5.15：单位按内容类型定 —— 任务「件」、日程「个」。 */
  private groupCountText(g: WeekGroup): string {
    if (g.eventCount === 0) { return `${g.taskCount} 件任务`; }
    if (g.taskCount === 0) { return `${g.eventCount} 个日程`; }
    return `${g.taskCount} 件任务 · ${g.eventCount} 个日程`;
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
      // v5.4：只画**跨天**的事。同一天的多件事各画一条只有 1/7 宽、标题必被截断，
      // 渲染出来是一堆看不懂的小药丸 ⇒ 同天的交给下面的「按天分组」列表。
      if (ei <= si) { continue; }
      out.push(ganttBar(t.title, si, ei, barBg(this.pal, t.area), barColor(this.pal, t.area), `${t.id}`));
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
      if (ei <= si) { continue; }   // v5.4：同上，同天的日程不画条
      out.push(ganttBar(e.title, si, ei, misc(this.pal, 'ganttBg', '#F2ECFF'), misc(this.pal, 'ganttFg', '#704DD2'), `e${e.id}`));
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
    return `${D.md(D.key(ws))} – ${D.md(D.key(D.dateAdd(ws, 6)))}`;
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
        hex: areaColor(this.pal, areas[i]),
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
   * 灵感派（v2.8 改成显示「随手记」里的内容，不再是待办任务）。
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
    const palette: string[] = paletteList(this.pal, 'spark5');
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
  /** v5.1：展开后的一行 —— 时间 + 标题 */
  @Builder
  noteLine(n: Note) {
    Row({  space: S.spaceLg  }) {
      Text(n.updated_at !== null && n.updated_at.length >= 10
        ? n.updated_at.substring(5, 10).replace('-', '/')
        : '')
        .fontSize(S.microSize)
        .fontColor(tc(this.pal, '#8FA2B3', 1))
      Text(this.noteTitle(n))
        .fontSize(S.bodySize)
        .fontColor(tk(this.pal, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({  top: S.spaceMd, bottom: S.spaceMd  })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onNavigate('notes'); })
  }

  /** v5.1：最近记的几条（按更新时间倒序，最多 6 条） */
  private recentNotes(): Note[] {
    const arr: Note[] = this.notes.filter((n: Note) => n.archived !== 1);
    for (let i = 0; i < arr.length; i++) {
      for (let j = i + 1; j < arr.length; j++) {
        const a: string = arr[i].updated_at !== null ? arr[i].updated_at : '';
        const b: string = arr[j].updated_at !== null ? arr[j].updated_at : '';
        if (b > a) {
          const tmp: Note = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
        }
      }
    }
    const n: number = Math.min(6, arr.length);
    return arr.slice(0, n);
  }

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

  /** v5.12：日期标签 —— 今天 / 明天 / 后天 / 11月20日 */
  private dayTagOf(dk: string, todayK: string): string {
    if (dk === todayK) { return '今天'; }
    if (dk === D.addDays(todayK, 1)) { return '明天'; }
    if (dk === D.addDays(todayK, 2)) { return '后天'; }
    return D.md(dk);
  }

  /** v5.12：这个习惯这天打卡了没 */
  private habitLogged(h: HabitView, day: string): boolean {
    return h.logs.indexOf(day) >= 0;
  }

  /** v5.12：点一下打卡 / 取消今天的打卡（打完 Store 会 notify ⇒ 首页立刻刷新） */
  private async checkHabit(h: HabitView): Promise<void> {
    const ok: boolean = await Store.I.toggleHabit(h.id, this.kHabitToday);
    if (!ok) {
      const msg: string = Store.I.lastError.length > 0 ? Store.I.lastError : '没打卡成功，再试一次';
      toast(this.getUIContext(), msg);
    }
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
    // v5.14：等写库结果出来再播报（原来先弹成功、再默默失败）。
    Store.I.setTaskStatus(t.id, next).then((ok: boolean) => {
      if (ok) {
        toast(this.getUIContext(), `「${t.title}」${label}`);
      } else {
        toast(this.getUIContext(), '状态没改成，再试一次');
      }
    });
  }

  private async doRefresh(): Promise<void> {
    await Store.I.loadAll();
    this.refreshing = false;
  }

  /** v5.1：按到期时间排序（逾期最久的排最前） */
  private cmpDue(a: Task, b: Task): number {
    const x: string = D.dateOf(a.due_date);
    const y: string = D.dateOf(b.due_date);
    if (x < y) { return -1; }
    if (x > y) { return 1; }
    return 0;
  }

  /** v5.1：今日清单里点圆圈 ⇒ 直接完成，并给一次撤销的机会 */
  private completeTask(t: Task): void {
    if (t.status === 'done') { return; }
    // v5.14：撤销条只在**真的写进库了**之后才出现。
    //   原来不管成没成都弹「已完成 + 撤销」，写失败时用户一点撤销还会再失败一次。
    Store.I.setTaskStatus(t.id, 'done').then((ok: boolean) => {
      if (!ok) {
        toast(this.getUIContext(), '没改成，再试一次');
        return;
      }
      this.undoTaskId = t.id;
      if (this.undoTimer > 0) { clearTimeout(this.undoTimer); }
      this.undoTimer = setTimeout(() => { this.undoTaskId = -1; }, 5000);
    });
  }

  /** v5.1：撤销刚才那一下（把它退回待办） */
  private undoComplete(): void {
    const id: number = this.undoTaskId;
    if (id < 0) { return; }
    this.undoTaskId = -1;
    if (this.undoTimer > 0) { clearTimeout(this.undoTimer); this.undoTimer = -1; }
    // v5.14：撤销失败也要说一声（原来是静默的）。
    Store.I.setTaskStatus(id, 'todo').then((ok: boolean) => {
      if (!ok) { toast(this.getUIContext(), '撤销没成功，再试一次'); }
    });
  }

  /** v5.1：今日清单一行右边的时间/逾期标记 */
  private todayWhen(t: Task): string {
    if (t.due_date === null) { return ''; }
    const dk: string = D.dateOf(t.due_date);
    const todayK: string = D.key(new Date());
    if (isOverdue(t)) {
      return `已逾期 ${overdueDays(t)} 天`;
    }
    if (dk === todayK) { return '今天'; }
    return dk.substring(5).replace('-', '/');
  }

  /** v5.1：逾期用红、今天用主色、以后用浅灰 */
  private todayWhenColor(t: Task): string {
    if (t.due_date === null) { return tk(this.pal, 'textHint'); }
    const dk: string = D.dateOf(t.due_date);
    const todayK: string = D.key(new Date());
    if (isOverdue(t)) { return tc(this.pal, '#D2795C', 1); }
    if (dk === todayK) { return tkInk(this.pal, 'brandDeep'); }
    return tk(this.pal, 'textHint');
  }

  // ── 小部件 ──
  /** 首页一行两块的排列方向：3 列时横排，1/2 列时竖排（手机外观不变） */
  /** v4.6 宽屏网格：列数 >= 3 时按网页端 .home-grid 的 2:1 跨度 + 14vp 真实间隙排 */
  /** v4.6：宽屏首页网格 —— 照网页端 .home-grid（3 列 + 14vp 间距 + 同行等高） */
  // 宽屏同行等高：各卡上报内容高度 → 取同行最大值 → 回填该行卡片的固定高度
  // v5.1：网格里只剩 3 张卡 —— ① 本周成长趋势 ② 本月成长日历（同一行） ③ 随手记（自己一行）
  @State contentH: number[] = [0, 0, 0];
  @State rowH: number[] = [0, 0];

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
    const r0: number = Math.max(arr[0], arr[1]);
    const r1: number = arr[2];
    this.rowH = [r0 + 2, r1 + 2];
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
    // v5.1：weight=3 表示「独占整行」
    if (weight >= 3 && c >= 2) {
      return c;
    }
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
    Row().width(w).height(h).backgroundColor(tc(this.pal, '#EAF2FA', 0)).borderRadius(S.radiusInner)
  }

  @Builder skeleton() {
    Column({  space: S.space2Xl  }) {
      Row().width('60%').height(24).backgroundColor(tc(this.pal, '#E3EDF7', 0)).borderRadius(S.radiusBtn)
      Row().width('45%').height(13).backgroundColor(tc(this.pal, '#EAF2FA', 0)).borderRadius(S.radiusSm)
      Row({  space: S.spaceLg  }) {
        this.skeletonBlock('48%', 78)
        this.skeletonBlock('48%', 78)
      }.width('100%')
      this.skeletonBlock('100%', 170)
      this.skeletonBlock('100%', 140)
      this.skeletonBlock('100%', 120)
    }
    .width('100%')
    .padding({  left: S.pagePad, right: S.pagePad, top: S.pageTop  })
    .alignItems(HorizontalAlign.Start)
  }

  /** .task-row 的一行 */
  @Builder taskRow(t: Task) {
    Row({  space: S.spaceXl  }) {
      StatusDot({
        status: t.status,
        dotSize: 20,
        onTap: () => { this.cycleStatus(t); }
      })

      Text(areaLabel(t.area))
        .fontSize(S.microSize)
        .fontColor(catColor(this.pal, t.area))
        .padding({  left: S.spaceLg, right: S.spaceLg, top: S.spaceXs, bottom: S.spaceXs  })
        .borderRadius(S.radiusSm)
        .backgroundColor(catBg(this.pal, t.area))

      Text(t.title)
        .fontSize(S.bodySize)
        .fontColor(t.status === 'done' ? tc(this.pal, '#A3B3C1', 1) : tk(this.pal, 'text'))
        .decoration({ type: t.status === 'done' ? TextDecorationType.LineThrough : TextDecorationType.None, color: '#A3B3C1' })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(this.taskMeta(t))
        .fontSize(S.tinySize)
        .fontColor(tc(this.pal, '#A2B3C2', 1))
        .maxLines(1)
        .flexShrink(0)

      // v4.23：fs14 墨迹 11.7x10.6vp（盒子 14x14 >= 12vp、墨迹 >= 8vp）
      SymbolGlyph(sym('right')).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#C2D0DB', 1)])
    }
    .width('100%')
    .padding({  left: S.spaceLg, right: S.spaceMd, top: S.spaceXl, bottom: S.spaceXl  })
    .borderRadius(S.radiusBtn)
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
  /** v5.1：今日清单的一行 —— 点圆圈直接完成 */
  @Builder todayRow(t: Task) {
    Row({  space: S.spaceXl  }) {
      // v5.6：这里原来自己画了一个圈，只有「已完成」和「其它」两种样子 ——
      // 任务在下面那张卡里被标成「进行中」（琥珀色）时，上面这里还是白圈，看着像没同步。
      // 现在直接用 StatusDot：待办=白空心圈 / 进行中=琥珀半色 / 已完成=薄荷绿实心。
      // 已完成的任务本来就被 openTasks() 过滤掉了，所以只有标绿才会从这里消失。
      StatusDot({
        status: t.status,
        dotSize: 20,
        onTap: () => { this.completeTask(t); }
      })

      Column({  space: S.spaceXs  }) {
        Text(t.title)
          .fontSize(S.bodySize)
          .fontColor(t.status === 'done' ? tk(this.pal, 'textFaint') : tk(this.pal, 'text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => { this.onNavigate('tasks'); })
        Text(this.todayWhen(t))
          .fontSize(S.microSize)
          .fontColor(this.todayWhenColor(t))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({  top: S.spaceLg, bottom: S.spaceLg  })
    .alignItems(VerticalAlign.Center)
  }

  /** v5.1：三个小入口块 —— 原来那个「核心模块」八宫格太满，只留最常用的三个 */
  @Builder entryTiles() {
    Row({  space: S.spaceLg  }) {
      this.entryTile('flame', '习惯打卡', '连续打卡', paletteAt(this.pal, 'entryBg', 0), paletteAt(this.pal, 'entryFg', 0), () => { this.onNavigate('habits'); })
      this.entryTile('target', '我的项目', '进度与截止', paletteAt(this.pal, 'entryBg', 1), paletteAt(this.pal, 'entryFg', 1), () => { this.onNavigate('projects'); })
      this.entryTile('note', '复盘笔记', '每天三分钟', paletteAt(this.pal, 'entryBg', 2), paletteAt(this.pal, 'entryFg', 2), () => { this.onNavigate('review'); })
    }
    .width('100%')
    .margin({  bottom: S.space3Xl  })
  }

  @Builder entryTile(icon: string, label: string, sub: string, bg: string, fg: string, cb: () => void) {
    Column({  space: S.spaceMd  }) {
      IconBox({ name: icon, boxSize: 30, iconSize: 15, radius: 10, bg: bg, fg: fg })
      Text(label)
        .fontSize(S.labelSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(tk(this.pal, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(sub)
        .fontSize(S.microSize)
        .fontColor(tk(this.pal, 'textHint'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({  top: S.space2Xl, bottom: S.space2Xl  })
    .borderRadius(S.radiusInner)
    .backgroundColor(tk(this.pal, 'card'))
    .border({ width: 1, color: tk(this.pal, 'cardBorder') })
    .onClick(cb)
  }

  @Builder eventRow(e: EventItem) {
    Row({  space: S.spaceLg  }) {
      Row().width(3).height(22).borderRadius(S.radiusDot).backgroundColor(tk(this.pal, 'event'))
      Text(e.all_day === 1 ? '全天' : D.hm(e.start_at))
        .fontSize(S.subSize)
        .fontColor(tk(this.pal, 'textSub'))
        .width(38)
      Text(e.title)
        .fontSize(S.subSize)
        .fontColor(tk(this.pal, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (e.location.length > 0) {
        Text(e.location)
          .fontSize(S.microSize)
          .fontColor(tk(this.pal, 'textHint'))
          .maxLines(1)
          .constraintSize({ maxWidth: 90 })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onNavigate('calendar'); })
  }

  /**
   * v5.5：整周视图 —— **只报数**。
   * v5.4 这里每天列 3 条标题，点开某天又换成另一种画法（带时间、带浅蓝框），
   * 同一批数据两种样子。现在整周每一天只写「N 条任务 / N 条日程」，
   * 点上面（或点这一天）才展开明细。
   */
  @Builder weekPanel() {
    Column({  space: 0  }) {
      if (this.kWeekGroups.length === 0) {
        Text('本周还没有安排到具体时间的事 · 点上面的日期看那天')
          .fontSize(S.microSize)
          .fontColor(tk(this.pal, 'textHint'))
          .padding({  top: S.space2Xl  })
      } else {
        ForEach(this.kWeekGroups, (g: WeekGroup) => {
          Row({  space: S.spaceMd  }) {
            Text(g.label)
              .fontSize(S.subSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(tk(this.pal, 'textSub'))
            Text(g.dateText)
              .fontSize(S.subSize)
              .fontColor(tk(this.pal, 'textFaint'))
            if (g.isToday) {
              Text('今天')
                .fontSize(S.microSize)
                .fontColor(tkInk(this.pal, 'brandDeep'))
                .padding({  left: S.spaceMd, right: S.spaceMd, top: S.spaceXs, bottom: S.spaceXs  })
                .borderRadius(S.radiusSm)
                .backgroundColor(tk(this.pal, 'brandSoft'))
            }
            // v5.5：条数放在左边。放右边会被右下角的悬浮「写一条」按钮压住。
            Text(this.groupCountText(g))
              .fontSize(S.subSize)
              .fontColor(tc(this.pal, '#5E7183', 1))
              .margin({  left: S.spaceSm  })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({  top: S.spaceLg, bottom: S.spaceLg  })
          .onClick(() => { this.dayPick = g.idx; this.recalc(); })
        }, (g: WeekGroup) => `wg-${g.idx}-${this.tick}`)
      }
    }
    .width('100%')
    .margin({  top: S.spaceXs  })
    .alignItems(HorizontalAlign.Start)
  }

  /** 排期任务一行 */
  @Builder weekTaskRow(t: Task) {
    Row({  space: S.spaceLg  }) {
      StatusDot({
        status: t.status,
        dotSize: 20,
        onTap: () => { this.cycleStatus(t); }
      })
      Text(t.title)
        .fontSize(S.subSize)
        .fontColor(tk(this.pal, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(t.scheduled_start !== null ? D.hm(t.scheduled_start) : '')
        .fontSize(S.microSize)
        .fontColor(tk(this.pal, 'textHint'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 选中某一天：那天具体的安排 */
  @Builder dayPanel() {
    Column({  space: S.spaceLg  }) {
      Row({  space: S.spaceMd  }) {
        Text(this.dayPickLabel())
          .fontSize(S.subSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(tk(this.pal, 'textSub'))
        // v5.5：「看整周」挪到左边。放右边会被右下角悬浮的「写一条」按钮压住。
        Text('看整周')
          .fontSize(S.tinySize)
          .fontColor(tkInk(this.pal, 'brandDeep'))
          .padding({  left: S.spaceLg, right: S.spaceLg, top: S.spaceSm, bottom: S.spaceSm  })
          .borderRadius(S.radiusSm)
          .backgroundColor(tk(this.pal, 'brandSoft'))
          .margin({  left: S.spaceLg  })
          .onClick(() => { this.dayPick = -1; })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.kDayEvents.length === 0 && this.kDayTasks.length === 0) {
        Text('这天还没有安排。')
          .fontSize(S.tinySize)
          .fontColor(tc(this.pal, '#B9CAD8', 1))
          .padding({  top: S.spaceSm, bottom: S.spaceSm  })
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
    .margin({  top: S.spaceXl  })
    .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceXl, bottom: S.spaceXl  })
    .borderRadius(S.radiusBtn)
    .backgroundColor(tc(this.pal, '#F7FBFE', 0))
    .border({ width: 1, color: tc(this.pal, tc(this.pal, '#E6F0F8', 2), 2) })
    .alignItems(HorizontalAlign.Start)
  }

  // 顶部栏（对齐工作台 TopBar 手机端：搜索 / 提醒 / 日历 + 主操作）
  @Builder pageTop() {
    TopBar({
      primaryText: '添加任务',
      onPrimary: () => { this.openSheet(); },
      onSearch: () => { this.onNavigate('search'); },
      // v5.1：日历按钮去掉（和底栏「日历安排」重复）
      showCalendar: false
    })
      .width('100%')
  }

  // ── 5 个 KPI（v4.6 抽成 builder，手机两列 / 平板一排 5 个）──
  @Builder kpiToday() {
    Column() {
      Kpi({
        label: '我的任务', icon: 'tasks', value: `${this.kAllTasks}`,
        numValue: this.kAllTasks,
        unit: '件', sub: `已完成 ${this.kDoneCount} 件`, pct: this.kAllPct
      })
    }.layoutWeight(1)
  }

  @Builder kpiRate() {
    Column() {
      Kpi({
        label: '完成率', icon: 'checkCircle', iconBg: catBg(this.pal, 'study'), iconFg: misc(this.pal, 'kpiRateFg', '#267261'),
        value: `${this.kAllPct}`, numValue: this.kAllPct, unit: '%',
        sub: this.kPctSubShort,
        subColor: tkInk(this.pal, 'brandDeep'), pct: this.kAllPct
      })
    }.layoutWeight(1)
  }

  @Builder kpiStreak() {
    Column() {
      Kpi({
        label: '最长连续', icon: 'flame', iconBg: paletteAt(this.pal, 'entryBg', 0), iconFg: paletteAt(this.pal, 'entryFg', 0),
        value: `${this.kHabitStreak}`, numValue: this.kHabitStreak,
        unit: '天', sub: this.kHabitSubShort,
        pct: this.kHabitPct
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
            Column({  space: 0  }) {
              Text(`${this.tick}`).fontSize(S.hiddenSize).width(1).height(1).opacity(0)

              this.pageTop()

              // ① hello：eyebrow + h1 + 副文案（v4.2：右上角显示设置里的「称呼」）
              Column({  space: S.spaceMd  }) {
                Row({  space: S.spaceMd  }) {
                  Text(D.mdWeek(D.key(new Date())))
                    .fontSize(S.tinySize)
                    .fontColor(tc(this.pal, '#9DB0C1', 1))
                    .letterSpacing(1.6)
                  Blank()
                  if (this.kUserName.length > 0) {
                    Row({  space: S.spaceSm  }) {
                      SymbolGlyph(sym('person')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'brandDeep')])
                      Text(this.kUserName)
                        .fontSize(S.tinySize)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(tkInk(this.pal, 'brandDeep'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .padding({  left: S.spaceLg, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
                    .borderRadius(S.radiusPill)
                    .backgroundColor(tk(this.pal, 'brandSoft'))
                    .alignItems(VerticalAlign.Center)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                Text(this.kHeaderTitle)
                  .fontSize(S.titleSize)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(tk(this.pal, 'text'))
                  .letterSpacing(-0.6)
                  .lineHeight(32)
                Text(this.kHeaderSub)
                  .fontSize(S.labelSize)
                  .fontColor(tk(this.pal, 'textSub'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({  top: S.spaceXl, bottom: S.space3Xl  })

              // v3.0：所有内容入口（任务 / 记录 / 日程 / 项目 / 复盘 / 习惯，一处看全）
              Row({  space: S.spaceMd  }) {
                SymbolGlyph(sym('grid')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'brandDeep')])
                Text('所有内容').fontSize(S.subSize).fontWeight(FontWeight.Medium).fontColor(tkInk(this.pal, 'brandDeep'))
                Text('一处看全').fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint'))
                // v4.23：fs14 墨迹 11.7x10.6vp（盒子 14x14 >= 12vp、墨迹 >= 8vp）
                SymbolGlyph(sym('right')).fontSize(S.cardTitleSize).fontColor([tk(this.pal, 'textHint')])
              }
              .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceMd, bottom: S.spaceMd  })
              .margin({  bottom: S.spaceXl  })
              .borderRadius(S.radiusPill)
              .backgroundColor(tk(this.pal, 'brandSoft'))
              .border({ width: 1, color: tk(this.pal, 'brandLine') })
              .alignItems(VerticalAlign.Center)
              .onClick(() => { this.onNavigate('all'); })

              // ② KPI 区（v5.16：三个数并成一行，手机也是三列）
              // v4.26：中间档（平板竖屏）走 3 + 2，和网页端 @media(max-width:1180px) 的 .kpis{repeat(3,1fr)} 对齐。
              // v5.1：KPI 从 5 个减到 3 个（专注时长只在趋势图里，成长积分彻底不要）。
              // v5.16：以前手机是「2 个一行 + 第 3 个独占一整行」，第三张孤零零地横在下面，
              //   看着像没排好；现在手机、平板都是一行三列。
              //   为了三列在手机上放得下，副文案也收短了（长文案在下面的「今天该打卡」卡里）。
              // v5.1（空状态）：整个库是空的 ⇒ 三个 0 全部收起，不给人看一片零；
              //   没有习惯 ⇒ 习惯那一块也不出现（「宁可少一块，也不要一块空的」）。
              if (!this.kAllEmpty) {
                Column() {
                  Row({  space: S.spaceLg  }) {
                    this.kpiToday()
                    this.kpiRate()
                    if (this.kHasHabits) { this.kpiStreak() }
                  }
                  .width('100%')
                }
                .width('100%')
                .margin({  bottom: S.space3Xl  })
              }

              // v5.13：原来这里有一行「「习惯打卡」= 现在还连着的最长天数（今天还没打卡不打断）；
              //   历史最长写在副标题里」—— 那是给开发者看的口径说明，用户看不懂也不需要知道。
              //   KPI 卡自己的副标题已经写清楚了（「今天的习惯都打卡了 · 历史最长 N 天」），这行删掉，
              //   首屏因此省下 30vp。
              // ═══════ v5.1：首页第一屏 —— 两张卡各管一件事 ═══════
              // ①「今天要做的」：只有今天的事（逾期置顶 → 今天 → 往后）。点圆圈直接完成（带撤销）。
              // ②「这一周」：周条 + 周明细 + 领域色例。
              //   （v5.1 第一版把这两件事塞在同一张卡里 ⇒ 一个标题下两个主题，看着挤、读不出重点。
              //    v5.2 拆成两张卡。）
              // v5.17：宽屏时「今天要做的」占 2 列、「这一周」占 1 列
              //   （照网页端 .home-grid 的 .span2 / 普通卡；窄屏自动退化成单列竖排）
              GridRow({ columns: this.gridCols(), gutter: { x: 14, y: 14 } }) {
              GridCol({ span: this.spanFor(2) }) {
              Column() {
              Card({
                // v5.0：入场逐个浮现
                appearDelay: 0,
                title: '今天要做的',
                sub: this.kTodayList.length > 0 ? `今天 ${this.kTodayList.length + this.kTodayRest} 件` : '',
                headMode: 'text', headText: '查看全部 ›', onHead: () => { this.onNavigate('tasks'); }
              }) {
                Column({  space: S.spaceXs  }) {
                  if (this.kTodayList.length === 0) {
                    // 空态压成一行，不占地方
                    Row({  space: S.spaceLg  }) {
                      SymbolGlyph(sym('calendar')).fontSize(S.headSize)
                        .fontColor([this.kLoadError.length > 0 ? tk(this.pal, 'danger') : tk(this.pal, 'textHint')])
                      // v5.14：库读不出来时别装成「没有任务」——
                      //   原来整库读取失败也显示空列表，用户以为数据被清了。
                      Text(this.kLoadError.length > 0
                        ? `数据没读出来：${this.kLoadError}`
                        : (this.kTotalTasks === 0 ? '还没有任务，先加一件今天想做的事。' : '今天没有到期的事，去任务面板看看。'))
                        .fontSize(this.kLoadError.length > 0 ? 12 : S.subSize)
                        .fontColor(this.kLoadError.length > 0 ? tk(this.pal, 'danger') : tk(this.pal, 'textHint'))
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({  top: S.spaceXl, bottom: S.spaceXl  })
                    .alignItems(VerticalAlign.Center)
                  } else {
                    ForEach(this.kTodayList, (t: Task) => {
                      this.todayRow(t)
                    }, (t: Task) => `td-${t.id}-${t.status}-${this.tick}`)
                  }

                  // 已完成的沉底：折成一行，不跟未完成的一起占地方
                  if (this.kTodayDoneCount > 0) {
                    Row({  space: S.spaceMd  }) {
                      SymbolGlyph(sym('check')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'done')])
                      Text(`今天完成 ${this.kTodayDoneCount} 件 · 查看`)
                        .fontSize(S.subSize).fontColor(tk(this.pal, 'textFaint'))
                    }
                    .width('100%')
                    .margin({  top: S.spaceXl  })
                    .alignItems(VerticalAlign.Center)
                    .onClick(() => { this.onNavigate('tasks'); })
                  }

                  if (this.kTodayRest > 0) {
                    Row({  space: S.spaceMd  }) {
                      Text(`还有 ${this.kTodayRest} 件今天要做`).fontSize(S.subSize).fontColor(tk(this.pal, 'textFaint'))
                      Blank()
                      Text('去任务面板 →')
                        .fontSize(S.subSize).fontColor(tc(this.pal, '#5E7183', 1))
                        .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
                        .borderRadius(S.radiusSm)
                        .backgroundColor(tk(this.pal, 'card'))
                        .border({ width: 1, color: tk(this.pal, 'line') })
                        .onClick(() => { this.onNavigate('tasks'); })
                    }
                    .width('100%')
                    .margin({  top: S.spaceXl  })
                    .alignItems(VerticalAlign.Center)
                  }

                  // v5.13：到期日在今天之后的那堆，单独一行说清楚，不混进「今天」
                  if (this.kSoonCount > 0) {
                    Row({  space: S.spaceMd  }) {
                      Text(`另有 ${this.kSoonCount} 件排在后面`).fontSize(S.subSize).fontColor(tk(this.pal, 'textFaint'))
                      Blank()
                      Text('去任务面板 →')
                        .fontSize(S.subSize).fontColor(tc(this.pal, '#5E7183', 1))
                        .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
                        .borderRadius(S.radiusSm)
                        .backgroundColor(tk(this.pal, 'card'))
                        .border({ width: 1, color: tk(this.pal, 'line') })
                        .onClick(() => { this.onNavigate('tasks'); })
                    }
                    .width('100%')
                    .margin({  top: S.spaceXl  })
                    .alignItems(VerticalAlign.Center)
                  }

                  // 直接打勾之后的撤销条（5 秒）
                  if (this.undoTaskId > 0) {
                    Row({  space: S.spaceLg  }) {
                      Text('已完成').fontSize(S.subSize).fontColor(tk(this.pal, 'text'))
                      Blank()
                      Text('撤销')
                        .fontSize(S.subSize)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(tkInk(this.pal, 'brandDeep'))
                        .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
                        .borderRadius(S.radiusSm)
                        .backgroundColor(tk(this.pal, 'brandSoft'))
                        .onClick(() => { this.undoComplete(); })
                    }
                    .width('100%')
                    .margin({  top: S.spaceXl  })
                    .padding({  left: S.spaceXl, right: S.spaceSm, top: S.spaceSm, bottom: S.spaceSm  })
                    .borderRadius(S.radiusBtn)
                    .backgroundColor(tc(this.pal, '#F2F8FD', 0))
                  }

                }
                .width('100%')
              }
              }
              .width('100%')
              }
              // ── ②「这一周」：从 ① 里拆出来，独立成卡 ──
              GridCol({ span: this.spanFor(1) }) {
              Column() {
              Card({
                appearDelay: 70,
                title: '这一周',
                sub: this.kWeekRange,
                headMode: 'text', headText: '日历 ›', onHead: () => { this.onNavigate('calendar'); }
              }) {
                Column({  space: 0  }) {
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

                  Row({  space: S.spaceXl  }) {
                    ForEach(['work', 'side', 'media', 'study', 'life'], (a: string) => {
                      Row({  space: S.spaceSm  }) {
                        Row().width(6).height(6).borderRadius(S.radiusDot).backgroundColor(areaColor(this.pal, a))
                        Text(areaLabel(a)).fontSize(S.microSize).fontColor(tk(this.pal, 'textHint'))
                      }
                    }, (a: string) => `wf-${a}`)
                  }
                  .width('100%')
                  .margin({  top: S.spaceLg  })
                }
                .width('100%')
              }
              }
              .width('100%')
              }
              }
              .width('100%')
              .margin({  bottom: S.space3Xl  })

              // v5.1：三个小入口块（原来那个「核心模块」八宫格太满，只留最常用的三个）
              this.entryTiles()

              // v4.6：宽屏时 ③–⑩ 照网页端 .home-grid 排版：
              // 一行两块 —— 宽的（趋势 / 最近任务 / 核心模块 / 灵感派）占 2 列，
              // 窄的（投入占比 / 成长日历 / 本周小结 / 今日一句）占 1 列；
              // 同一行的两块拉齐高度，不留参差不齐的空当（手机上仍是单列顺序排）。
              Column() {
              GridRow({ columns: this.gridCols(), gutter: { x: 14, y: 14 } }) {              // ③ 接下来 + ⑥ 今天该打卡
              // v5.12：原来这里是「本周成长趋势」和「本月成长日历」——
              // 趋势画的是任务的「估算时长」（App 里没有计时器，多数任务没填估时 ⇒ 曲线几乎是 0），
              // 月历只数每天完成几项（和上面 KPI 的「完成率」重复）⇒ 换成两张真能用的：
              // ③ 接下来：未来 7 天的安排 + 逾期提醒；⑥ 今天该打卡：点一下就打卡。
              GridCol({ span: this.spanFor(2) }) {
                Column() {
                  Card({
                    // v5.0：入场逐个浮现
                    appearDelay: 0,
                    fixedHeight: this.gridWide() ? this.rowH[0] : 0,
                    onContentHeight: (h: number) => { this.setContentH(0, h); },
                    title: '接下来', sub: '未来 7 天的安排',
                    headMode: 'text', headText: '日历 ›',
                    onHead: () => { this.onNavigate('calendar'); }
                  }) {
                    Column({  space: S.spaceLg  }) {
                      if (this.kNextOverdue > 0) {
                        Row({  space: S.spaceMd  }) {
                          Text(`${this.kNextOverdue} 件已经逾期`).fontSize(S.subSize).fontColor(tc(this.pal, '#A83440', 1))
                          Blank()
                          Text('去处理 ›').fontSize(S.tinySize).fontColor(tc(this.pal, '#A83440', 1))
                        }
                        .width('100%')
                        .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceMd, bottom: S.spaceMd  })
                        .borderRadius(S.radiusSm)
                        .backgroundColor(tc(this.pal, '#FDEDEA', 0))
                        .onClick(() => { this.onNavigate('tasks'); })
                      }
                      if (this.kNextEvents.length === 0) {
                        Column({  space: S.spaceSm  }) {
                          Text('接下来 7 天没有安排。').fontSize(S.bodySize).fontColor(tk(this.pal, 'textFaint'))
                          Text('有空就把想做的事记下来。').fontSize(S.subSize).fontColor(tk(this.pal, 'textPale'))
                        }
                        .width('100%')
                        .padding({  top: S.spaceXl, bottom: S.spaceXl  })
                        .alignItems(HorizontalAlign.Start)
                      } else {
                        ForEach(this.kNextEvents, (e: NextEvent) => {
                          Row({  space: S.spaceLg  }) {
                            Text(e.dayLabel)
                              .fontSize(S.microSize)
                              .fontColor(e.isToday ? tkInk(this.pal, 'brandDeep') : tk(this.pal, 'textSub'))
                              .width(56)
                              .textAlign(TextAlign.Center)
                              .padding({  left: S.spaceXs, right: S.spaceXs, top: S.spaceXs, bottom: S.spaceXs  })
                              .borderRadius(S.radiusXs)
                              .backgroundColor(e.isToday ? tk(this.pal, 'brandSoft') : tc(this.pal, '#F1F7FC', 0))
                            Text(e.timeLabel).fontSize(S.tinySize).fontColor(tk(this.pal, 'textSub')).width(38)
                            Text(e.title).fontSize(S.bodySize).fontColor(tk(this.pal, 'text')).maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                          }
                          .width('100%')
                          .alignItems(VerticalAlign.Center)
                          .onClick(() => { this.onNavigate('calendar'); })
                        }, (e: NextEvent) => `ne-${e.id}-${this.tick}`)
                        if (this.kNextMore > 0) {
                          Text(`还有 ${this.kNextMore} 条 ›`).fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint')).width('100%')
                        }
                      }
                    }
                    .width('100%')
                  }

                }
              }
              // ⑥ 今天该打卡
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  Card({
                    // v5.0：入场逐个浮现
                    appearDelay: 180,
                    fixedHeight: this.gridWide() ? this.rowH[0] : 0,
                    onContentHeight: (h: number) => { this.setContentH(1, h); },
                    title: '今天该打卡', sub: '点一下就打卡',
                    headMode: 'text', headText: '全部 ›',
                    onHead: () => { this.onNavigate('habits'); }
                  }) {
                    Column({  space: S.spaceXl  }) {
                      if (this.kHabitRows.length === 0) {
                        Column({  space: S.spaceSm  }) {
                          Text('还没有习惯').fontSize(S.bodySize).fontColor(tk(this.pal, 'textFaint'))
                          Text('加一个每天都要做的小事。').fontSize(S.subSize).fontColor(tk(this.pal, 'textPale'))
                        }
                        .width('100%')
                        .padding({  top: S.spaceXl, bottom: S.spaceXl  })
                        .alignItems(HorizontalAlign.Start)
                      } else {
                        Text(this.kHabitPending2 === 0 ? '今天的都打卡了' : `今天还有 ${this.kHabitPending2} 个没打卡`)
                          .fontSize(S.subSize)
                          .fontColor(tk(this.pal, 'textSub'))
                          .width('100%')
                        ForEach(this.kHabitRows, (h: HabitView) => {
                          Column({  space: S.spaceMd  }) {
                            Row({  space: S.spaceMd  }) {
                              Text(h.name).fontSize(S.bodySize).fontColor(tk(this.pal, 'text')).maxLines(1)
                                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                              Text(h.streak > 0 ? `连续 ${h.streak} 天` : '刚开始').fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint'))
                            }
                            .width('100%')
                            Row({  space: S.spaceSm  }) {
                              ForEach(this.kHabitDays, (day: string) => {
                                Row()
                                  .width(14).height(14).borderRadius(S.radiusSm)
                                  .backgroundColor(this.habitLogged(h, day) ? h.color : tc(this.pal, '#EDF4FA', 0))
                                  .border({ width: 1, color: this.habitLogged(h, day) ? h.color : (day === this.kHabitToday ? tk(this.pal, 'brand') : tc(this.pal, '#E4EFF8', 2)) })
                              }, (day: string) => `hd-${h.id}-${day}-${this.tick}`)
                            }
                            .width('100%')
                          }
                          .width('100%')
                          .onClick(() => { this.checkHabit(h); })
                        }, (h: HabitView) => `hr-${h.id}-${this.tick}`)
                      }
                    }
                    .width('100%')
                  }

                }
              }

              // ⑨ 灵感派
              // v5.1：③ 随手记（原来叫「灵感派」）—— 独占一行，点一下展开那几条
              GridCol({ span: this.spanFor(3) }) {
                Column() {
                  Card({
                    // v5.0：入场逐个浮现
                    appearDelay: 240,
                      fixedHeight: this.gridWide() ? this.rowH[1] : 0,
                      onContentHeight: (h: number) => { this.setContentH(2, h); },
                      title: '随手记', sub: '随手记里的几条',
                    headMode: 'text', headText: '全部 ›',
                    onHead: () => { this.onNavigate('notes'); }
                  }) {
                    Column({  space: S.spaceXl  }) {
                      if (this.kCandCount === 0) {
                        Column({  space: S.spaceMd  }) {
                          Text('还没有记录').fontSize(S.bodySize).fontColor(tk(this.pal, 'textFaint'))
                          Text('随手记下第一条记录。').fontSize(S.subSize).fontColor(tk(this.pal, 'textPale'))
                        }
                        .width('100%')
                        .padding({  top: S.space3Xl, bottom: S.space3Xl  })
                        .alignItems(HorizontalAlign.Center)
                      } else {
                        Column() {
                          Donut({ pieces: this.kCandPieces, boxSize: 118, holeSize: 22 })
                        }
                        .width(118)
                        .height(118)
                        .borderRadius(59)
                        .backgroundColor(tk(this.pal, 'card'))
                        .justifyContent(FlexAlign.Center)
                        .onClick(() => { this.spin += 1; })

                        Column({  space: S.spaceXs  }) {
                          ForEach(this.kCandItems.slice(0, 3), (c: CandItem, idx: number) => {
                            Column({  space: S.spaceSm  }) {
                              Row({  space: S.spaceLg  }) {
                                Row() {
                                  Text(`${idx + 1}`).fontSize(S.microSize).fontColor(idx === 0 ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#8FA2B3', 1))
                                }
                                .width(16)
                                .height(16)
                                .borderRadius(S.radiusSm)
                                .backgroundColor(idx === 0 ? tk(this.pal, 'brandSoft') : tc(this.pal, '#F1F7FC', 0))
                                .justifyContent(FlexAlign.Center)
                                .alignItems(VerticalAlign.Center)
                                Text(c.title)
                                  .fontSize(S.subSize)
                                  .fontColor(tk(this.pal, 'text'))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                                  .layoutWeight(1)
                                Text(`${c.pct}%`).fontSize(S.microSize).fontColor(tc(this.pal, '#8FA2B3', 1))
                              }
                              .width('100%')
                              .padding({  top: S.spaceMd, bottom: S.spaceSm  })
                              .alignItems(VerticalAlign.Center)

                              Row() {
                                Row()
                                  .width(`${c.pct}%`)
                                  .height(4)
                                  .borderRadius(S.radiusDot)
                                  .backgroundColor(c.color)
                              }
                              .width('100%')
                              .height(4)
                              .borderRadius(S.radiusDot)
                              .backgroundColor(tk(this.pal, 'track'))
                            }
                            .width('100%')
                            .onClick(() => { this.onNavigate('notes'); })
                          }, (c: CandItem) => `cand-${c.id}-${c.pct}-${this.tick}`)

                          Text('从记下的东西里，挑一条现在就动手。')
                            .fontSize(S.microSize + 0.5)
                            .fontColor(tk(this.pal, 'textHint'))
                            .margin({  top: S.spaceMd  })
                        }
                        .width('100%')

                        // v5.1：就地展开最近记的几条 —— 不跳页
                        if (this.notesOpen) {
                          Divider()
                            .color(tk(this.pal, 'line'))
                            .strokeWidth(1)
                            .margin({  top: S.spaceLg, bottom: S.spaceSm  })

                          ForEach(this.recentNotes(), (n: Note) => {
                            this.noteLine(n)
                          }, (n: Note) => `rn-${n.id}-${this.tick}`)

                          Text(`共 ${this.notes.length} 条 · 全部 ›`)
                            .fontSize(S.microSize + 0.5)
                            .fontColor(tkInk(this.pal, 'brandDeep'))
                            .width('100%')
                            .margin({  top: S.spaceMd  })
                            .onClick(() => { this.onNavigate('notes'); })
                        } else {
                          Text('▾ 看看最近记了什么')
                            .fontSize(S.microSize + 0.5)
                            .fontColor(tkInk(this.pal, 'brandDeep'))
                            .width('100%')
                            .margin({  top: S.spaceMd  })
                            .onClick(() => { this.notesOpen = true; })
                        }
                      }
                    }
                    .width('100%')
                    .alignItems(HorizontalAlign.Center)
                  }

                }
              }
              }
              .alignItems(ItemAlign.Start)
              .width('100%')
              }
              .width('100%')
              .margin({  bottom: R.bottomPad()  })
            }
            .width('100%')
            .padding({  left: S.pagePad, right: S.pagePad, top: S.pageTop  })
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
        // v5.0：页面底色改成透明，让 Index 根 Stack 上的大光斑透出来
      .backgroundColor(Color.Transparent)
        .edgeEffect(EdgeEffect.Spring)
        // v4.5：滚动时把右下角悬浮按钮藏起来（它正好压在趋势图末点气泡上），停了就回来
        // v5.0：顺手把滚动偏移报给页面底色（背景光斑做 0.12 倍视差；超过 10px 才报，免得每帧都重画）
        .onDidScroll((x: number, y: number) => {
          AppStorage.setOrCreate<boolean>('wb_scrolling', true);
          this.lastScrollY = y;
          AppStorage.setOrCreate<number>('wb_scroll_y', y);
        })
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
