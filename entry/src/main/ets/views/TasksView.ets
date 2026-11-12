// 任务面板
// 对齐「个人工作台」components/TasksPage.tsx：page-head → tstats 4 个 → filters 胶囊
// → kanban 三列（手机上竖排）→ tasks-extra 两张卡（近七天收尾节奏 / 刚刚做完的）。
import { Store, isConsumedRepeat } from '../store/Store';
import { areaColor, areaLabel, C, catBg, catColor, onFill, S, tc, tk } from '../utils/Theme';
import { R } from '../utils/Responsive';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { Chip } from '../components/Widgets';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { display } from '@kit.ArkUI';
import { TaskSheet } from '../components/TaskSheet';
import { StatusDot } from '../components/StatusDot';
import { TopBar } from '../components/TopBar';
import { Task, TaskStatus } from '../api/Types';
import { SheetFrame } from '../components/SheetFrame';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

/** 拖拽落点：三个状态按钮在屏幕上的全局位置（vp） */
interface DropArea {
  status: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

@Component
export struct TasksView {
  @State tick: number = 0;
  // v4.6：宽屏档位（宽屏时弹层限宽）
  @StorageLink('wb_layout') layoutMode: number = 0;
  // v4.8：深色模式开关（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tasks: Task[] = [];
  @State area: string = 'all';
  @State due: string = 'all';
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
      this.sheetContent()
    }
  }

  @State editingId: number = -1;
  @State addStatus: string = 'todo';
  @State busy: boolean = false;
  @State dragId: number = -1;         // 正在拖的任务（>0 = 拖拽中）
  // v4.2：ArkUI V1 只刷新「属性表达式里直接读过 state」的节点，
  // 方法调用里读 state（this.byStatus()）不算依赖 ⇒ 计数全部预计算进 @State。
  @State cTodo: number = 0;           // 待办（当前筛选下）—— 列头 / 空态用
  @State cDoing: number = 0;          // 进行中
  @State cDone: number = 0;           // 已完成
  // v4.4：tstat 四格改用「全局」口径（网页版 TasksPage.tsx:268 就是全局），
  // 列头和空态用筛选后的 cTodo/cDoing/cDone —— 两套口径各司其职，不再互相打架。
  @State gTodo: number = 0;           // 待办（全部）
  @State gDoing: number = 0;          // 进行中（全部）
  @State gDone: number = 0;           // 已完成（全部）
  @State cOpen: number = 0;           // 未完成总数
  @State cOverdue: number = 0;        // 逾期数
  @State cForever: number = 0;        // 长期任务数（没有截止时间、还没做完）
  @State cDoneAll: number = 0;        // 累计完成
  @State cWeekDone: number = 0;       // 本周完成
  // v4.12：重复任务做完的「原件」收走，不计入总件数
  @State cTotal: number = 0;
  @State cLast7Avg: number = 0;       // 近七天日均
  @State dragX: number = 0;
  private dragStartX: number = 0;   // 卡片中心（vp），浮卡的起点
  private dragStartY: number = 0;           // 拖拽时手指位置（浮动卡片跟手）
  @State dragY: number = 0;
  @State dragTarget: string = '';      // 当前高亮的目标状态
  @State dragTitle: string = '';       // 正在拖的任务标题
  private dropAreas: DropArea[] = [];  // 三个落点的全局位置
  private cardAreas: Map<number, Area> = new Map();  // 每张卡片在屏幕上的位置
  private dragAt: number = 0;          // 长按发生的时间，用来挡掉长按后误触发的点击
  private suppressClick: boolean = false; // 长按后那一下点击不算「点卡片」
  private dragging: boolean = false;     // 长按之后有没有真的在拖
  private suppressTimer: number = -1;
  private unsub: () => void = () => {};

  /** v4.6：宽屏？ */
  private wideMode(): boolean {
    return this.layoutMode >= 1;
  }

  private syncStore(): void {
    this.tasks = Store.I.tasks;
    this.recount();
  }

  /** v4.2：把派生计数算好写进 @State，UI 里只直接读 state */
  private recount(): void {
    const list: Task[] = this.filtered();
    let todo: number = 0;
    let doing: number = 0;
    let done: number = 0;
    for (const t of list) {
      if (t.status === 'todo') { todo += 1; }
      else if (t.status === 'doing') { doing += 1; }
      else { done += 1; }
    }
    this.cTodo = todo;
    this.cDoing = doing;
    this.cDone = done;

    let open: number = 0;
    let over: number = 0;
    let doneAll: number = 0;
    let forever: number = 0;
    let gTodo: number = 0;
    let gDoing: number = 0;
    let gDone: number = 0;
    let consumed: number = 0;
    for (const t of this.tasks) {
      if (isConsumedRepeat(t)) { consumed += 1; }
      if (t.status === 'todo') { gTodo += 1; }
      else if (t.status === 'doing') { gDoing += 1; }
      else if (!isConsumedRepeat(t)) { gDone += 1; }
      if (t.status !== 'done') {
        open += 1;
        if (this.isOverdue(t)) { over += 1; }
        // v4.14：长期任务 = 没有截止时间的未完成任务
        if (!this.hasDue(t)) { forever += 1; }
      } else if (!isConsumedRepeat(t)) {
        // v4.12：已消耗的重复原件不计入统计
        doneAll += 1;
      }
    }
    this.cTotal = this.tasks.length - consumed;
    this.gTodo = gTodo;
    this.gDoing = gDoing;
    this.gDone = gDone;
    this.cOpen = open;
    this.cOverdue = over;
    this.cForever = forever;
    this.cDoneAll = doneAll;

    const ws: string = D.weekStart();
    let weekDone: number = 0;
    for (const t of this.tasks) {
      if (t.status === 'done' && !isConsumedRepeat(t) && t.done_at !== null && D.dateOf(t.done_at) >= ws) { weekDone += 1; }
    }
    this.cWeekDone = weekDone;

    let sum: number = 0;
    const series: number[] = this.last7();
    for (const n of series) { sum += n; }
    this.cLast7Avg = sum / 7;
  }
  onNavigate: (page: string) => void = () => {};
  onLogout: () => void = () => {};

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  // ── 数据 ──
  private filtered(): Task[] {
    const now = new Date();
    const ws = D.parse(D.weekStart());
    const out: Task[] = [];
    for (const t of this.tasks) {
      if (this.area !== 'all' && t.area !== this.area) { continue; }
      if (this.due === 'today') {
        // v4.4：已完成的不该再出现在「今天」里（网页 TasksPage.tsx:129 也这么过滤）
        if (t.status === 'done') { continue; }
        if (!this.hasDue(t) || !D.sameDay(t.due_date as string, now)) { continue; }
      } else if (this.due === 'week') {
        if (t.status === 'done') { continue; }
        if (!this.hasDue(t)) { continue; }
        const d = D.parse(t.due_date as string);
        if (D.diffDays(d, ws) < 0 || D.diffDays(d, ws) > 6) { continue; }
      } else if (this.due === 'overdue') {
        if (t.status === 'done') { continue; }
        if (!this.isOverdue(t)) { continue; }
      } else if (this.due === 'forever') {
        // v4.14：长期任务筛选 —— 没设截止时间、还没做完的
        if (t.status === 'done') { continue; }
        if (this.hasDue(t)) { continue; }
      }
      out.push(t);
    }
    return out;
  }

  private byStatus(s: string): Task[] {
    const out: Task[] = [];
    for (const t of this.filtered()) {
      if (t.status !== s) { continue; }
      // v4.12：重复任务做完的「原件」收走 —— 不留在已完成列里
      if (s === 'done' && isConsumedRepeat(t)) { continue; }
      out.push(t);
    }
    return out;
  }

  /** 有没有填到期日（空字符串/null 都算没填） */
  private hasDue(t: Task): boolean {
    return t.due_date !== null && t.due_date !== undefined && t.due_date.length > 0;
  }

  /**
   * v4.4 逾期口径（跟网页版 components/TasksPage.tsx:199 一致）：
   *   没完成 + 填了到期日 + 到期日早于今天（按日历日比，不看具体时刻）
   * 用字符串比日期，不走 D.parse —— 空值会被 parse 成 1899 年，
   * 那会让「没填到期日」的任务全部变成逾期。
   */
  private isOverdue(t: Task): boolean {
    if (t.status === 'done') { return false; }
    if (!this.hasDue(t)) { return false; }
    return (t.due_date as string).slice(0, 10) < D.today();
  }

  /** 逾期几天（用来在卡片上写「逾期 3 天」） */
  private overdueDays(t: Task): number {
    if (!this.isOverdue(t)) { return 0; }
    const days: number = -D.diffDays(D.parse((t.due_date as string).slice(0, 10)), new Date());
    return days > 0 ? days : 0;
  }

  // ── 状态流转（v2.8）────────────────────────────────────────
  /** 圈圈点击：待办 → 进行中 → 完成 → 待办（工作台是完成↔待办，这里多一档进行中） */
  private cycleStatus(t: Task): void {
    const next: TaskStatus = t.status === 'todo' ? 'doing' : (t.status === 'doing' ? 'done' : 'todo');
    this.applyStatus(t.id, next, t.title);
  }

  private applyStatus(id: number, status: TaskStatus, title: string): void {
    const label: string = status === 'done' ? '完成了' : (status === 'doing' ? '开始做了' : '退回待办了');
    Store.I.setTaskStatus(id, status).catch(() => {
      toast(this.getUIContext(), '状态没改成，再试一次');
    });
    toast(this.getUIContext(), `「${title}」${label}`);
  }

  private findTaskLocal(id: number): Task | null {
    for (const t of this.tasks) { if (t.id === id) { return t; } }
    return null;
  }

  // ── 长按拖拽改状态（v2.8）──────────────────────────────────
  private startDrag(t: Task): void {
    this.dragId = t.id;
    this.dragging = false;
    this.dragTitle = t.title;
    this.dragTarget = '';
    this.dragAt = Date.now();
    // 浮动卡片从被按住的卡片位置冒出来
    const area = this.cardAreas.get(t.id);
    if (area !== undefined) {
      this.dragStartX = this.numOf(area.globalPosition.x) + this.numOf(area.width) / 2;
      this.dragStartY = this.numOf(area.globalPosition.y) + this.numOf(area.height) / 2;
    }
    this.dragX = this.dragStartX;
    this.dragY = this.dragStartY;
    this.dropAreas = [];
    this.clampDrag();
    // 拖拽时右下角的「快速记一笔」会压住「完成」落点，先让它藏起来
    AppStorage.setOrCreate<boolean>('wb_dragging', true);
    // 长按之后松手时 ArkUI 还会补一个 click，这里先把它挡掉
    this.suppressClick = true;
    if (this.suppressTimer >= 0) { clearTimeout(this.suppressTimer); }
    this.suppressTimer = setTimeout(() => {
      this.suppressClick = false;
      this.suppressTimer = -1;
    }, 1500);
  }

  private endDrag(): void {
    this.dragId = -1;
    this.dragging = false;
    this.dragTarget = '';
    this.dropAreas = [];
    AppStorage.setOrCreate<boolean>('wb_dragging', false);
  }

  /** Area / Position 的长度是 Length（number | string | Resource），落点表只存数字 */
  private numOf(v: Length | undefined): number {
    if (typeof v === 'number') { return v; }
    return 0;
  }

  private recordArea(status: string, area: Area): void {
    const ax: number = this.numOf(area.globalPosition.x);
    const ay: number = this.numOf(area.globalPosition.y);
    const aw: number = this.numOf(area.width);
    const ah: number = this.numOf(area.height);
    for (const a of this.dropAreas) {
      if (a.status === status) {
        a.x = ax;
        a.y = ay;
        a.w = aw;
        a.h = ah;
        return;
      }
    }
    this.dropAreas.push({
      status: status,
      x: ax,
      y: ay,
      w: aw,
      h: ah
    });
  }

  /** 手指落在哪个状态按钮上 */
  private hitTest(x: number, y: number): void {
    let hit: string = '';
    for (const a of this.dropAreas) {
      if (x >= a.x && x <= a.x + a.w && y >= a.y && y <= a.y + a.h) { hit = a.status; break; }
    }
    this.dragTarget = hit;
  }

  private panUpdate(e: GestureEvent): void {
    const list = e.fingerList;
    if (list.length === 0) { return; }
    // v4.4 真机实测（hilog 实测过）：
    //   GestureEvent.fingerList[0].globalX/globalY 的单位就是 **vp**，
    //   而且和 onAreaChange 给的 globalPosition 是同一个坐标系
    //   （手指按在 (400,2505) 时 global=(114,716)，400/3.5=114、2505/3.5=716）。
    //   v4.4 中间那版又套了一次 px2vp，把位置缩到 1/3.5，浮卡全跑到左上角，落点也点不中。
    const vx: number = list[0].globalX;
    const vy: number = list[0].globalY;
    this.dragX = vx;
    this.dragY = vy;
    this.clampDrag();
    this.hitTest(vx, vy);
  }

  /** 浮卡是 200vp 宽，要保证它整个留在屏幕里 */
  private clampDrag(): void {
    // 全局 px2vp 在新 SDK 里已废弃 → 用 UIContext 的那个
    let sw: number = 360;
    let sh: number = 780;
    try {
      const d = display.getDefaultDisplaySync();
      sw = this.getUIContext().px2vp(d.width);
      sh = this.getUIContext().px2vp(d.height);
    } catch (e) {
      // 取不到屏幕尺寸就用兜底值，别让拖拽崩掉
    }
    const halfW: number = 100;
    const halfH: number = 74;
    this.dragX = Math.max(halfW + 4, Math.min(sw - halfW - 4, this.dragX));
    this.dragY = Math.max(halfH + 4, Math.min(sh - halfH - 4, this.dragY));
  }

  private panEnd(): void {
    const id: number = this.dragId;
    const target: string = this.dragTarget;
    const t: Task | null = this.findTaskLocal(id);
    this.endDrag();
    if (id > 0 && target.length > 0 && t !== null && t.status !== target) {
      this.applyStatus(id, target as TaskStatus, t.title);
    }
  }

  private targetLabel(status: string): string {
    if (status === 'todo') { return '待办'; }
    if (status === 'doing') { return '进行中'; }
    return '已完成';
  }

  private statusHint(status: string): string {
    if (status === 'todo') { return '退回待办'; }
    if (status === 'doing') { return '正在做'; }
    return '标记完成';
  }

  /** 近 7 天每天完成数 */
  private last7(): number[] {
    const out: number[] = [];
    for (let i = 6; i >= 0; i--) {
      const d = D.dateAdd(new Date(), -i);
      let n = 0;
      for (const t of this.tasks) {
        if (t.done_at !== null && D.sameDay(t.done_at, d)) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  private last7Label(i: number): string {
    const d = D.dateAdd(new Date(), -(6 - i));
    return `${D.slashMd(d)} 周${D.weekdayOf(D.key(d))}`;
  }

  private last7Max(): number {
    let m = 0;
    for (const n of this.last7()) { if (n > m) { m = n; } }
    return m;
  }

  private weekDoneCount(): number {
    const ws = D.weekStart();
    return this.tasks.filter((t: Task) => t.done_at !== null && D.dateOf(t.done_at) >= ws && t.status === 'done').length;
  }

  private recentDone(): Task[] {
    // v4.12：重复任务做完的「原件」收走 —— 不进「刚刚做完的」
    const list: Task[] = this.tasks.filter((t: Task) => t.status === 'done' && !isConsumedRepeat(t) && t.done_at !== null);
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        let a: string = '';
        let b: string = '';
        const ia: string | null = list[i].done_at;
        const ib: string | null = list[j].done_at;
        if (ia !== null) { a = ia; }
        if (ib !== null) { b = ib; }
        if (b > a) {
          const t = list[i]; list[i] = list[j]; list[j] = t;
        }
      }
    }
    return list.slice(0, 4);
  }

  // ── 组件 ──
  @Builder tstat(cls: string, dot: string, label: string, status: string, warn: boolean) {
    Row({ space: 9 }) {
      Row() {
        Row().width(8).height(8).borderRadius(4).backgroundColor(dot)
      }
      .width(28)
      .height(28)
      .borderRadius(9)
      .backgroundColor(cls)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 1 }) {
        Text(label).fontSize(S.tinySize).fontColor(tc(this.dark, '#8FA2B3', 1))
        Row({ space: 2 }) {
          Text(status === 'todo' ? `${this.gTodo}` : (status === 'doing' ? `${this.gDoing}` : (status === 'done' ? `${this.gDone}` : `${this.cOverdue}`)))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(warn && this.cOverdue > 0 ? tc(this.dark, '#C25E4A', 1) : tc(this.dark, '#2B4055', 1))
          Text('件').fontSize(9).fontColor(tk(this.dark, 'textHint')).margin({ bottom: 1 })
        }
        .alignItems(VerticalAlign.Bottom)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .padding({ left: 12, right: 10, top: 8, bottom: 8 })
    .borderRadius(S.radiusInner)
    .backgroundColor(tk(this.dark, 'card'))
    .border({ width: 1, color: tk(this.dark, 'cardBorder') })
    .alignItems(VerticalAlign.Center)
  }

  @Builder boardCard(t: Task) {
    Column({ space: 6 }) {
      Text(t.title)
        .fontSize(S.bodySize)
        .fontColor(t.status === 'done' ? tc(this.dark, '#A3B3C1', 1) : tc(this.dark, '#2C4257', 1))
        .decoration({ type: t.status === 'done' ? TextDecorationType.LineThrough : TextDecorationType.None, color: '#A3B3C1' })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ right: 18 })

      Row({ space: 6 }) {
        Text(this.hasDue(t) ? D.slashMd(D.parse((t.due_date as string).slice(0, 10))) : '长期')
          .fontSize(S.microSize)
          .fontColor(this.isOverdue(t) ? tc(this.dark, '#D2795C', 1) : tk(this.dark, 'textHint'))
        // v4.4：光把日期变红，看不出「逾期」这个状态 —— 加个明说的红标
        if (this.overdueDays(t) > 0) {
          Text(`逾期 ${this.overdueDays(t)} 天`)
            .fontSize(8)
            .fontColor(onFill(this.dark))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor(tc(this.dark, '#E08A6F', 0))
        }
        Text(areaLabel(t.area))
          .fontSize(8)
          .fontColor(tc(this.dark, '#8FA2B3', 1))
          .padding({ left: 5, right: 5, top: 0, bottom: 0 })
          .borderRadius(5)
          .border({ width: 1, color: tc(this.dark, tc(this.dark, '#EAF2F9', 2), 2) })
        if (t.priority === 'high') {
          Text('· 要紧').fontSize(S.microSize).fontColor(tc(this.dark, '#D2795C', 1))
        }
        if (t.estimate_min !== null && t.estimate_min > 0) {
          Text(`${t.estimate_min}m`).fontSize(S.microSize).fontColor(tk(this.dark, 'textHint'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 11, right: 11, top: 10, bottom: 10 })
    .borderRadius(S.radiusInner)
    .backgroundColor(tk(this.dark, 'card'))
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#EBF3FA', 2), 2) })
    .margin({ top: 7 })
    // 拖起来的卡片淡出（工作台 .tcard.lifted）
    .opacity(this.dragId === t.id ? 0.35 : 1)
    // v4.2：手指抬起来的时候收尾。Sequence 手势里「只长按没拖」不会有 pan 的 onActionEnd，
    // 遮罩层会一直挡着页面 —— 这里用 onTouch 的 Up 兜住。
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.dragId > 0 && !this.dragging) { this.endDrag(); }
      }
    })
    .onClick(() => {
      // 长按刚结束的那一下不要再弹编辑框
      if (this.suppressClick) { this.suppressClick = false; this.endDrag(); return; }
      if (Date.now() - this.dragAt < 800) { return; }
      this.editingId = t.id;
      this.addStatus = t.status;
      this.openSheet();
    })
    // 长按 → 拖到别的状态：先长按识别成功，之后的平移才算拖拽
    .gesture(
      GestureGroup(
        GestureMode.Sequence,
        // v4.4：长按 380ms / 8px 太钝，对齐网页版的 220ms / 5px（手指按住就走）
        LongPressGesture({ fingers: 1, repeat: false, duration: 220 })
          .onAction(() => { this.startDrag(t); })
          // 只按住了没动：松手就把遮罩收掉，不然整个页面会被挡住
          .onActionEnd(() => {
            if (this.dragId > 0 && !this.dragging) { this.endDrag(); }
          }),
        PanGesture({ distance: 5 })
          .onActionStart(() => { this.dragging = true; })
          .onActionUpdate((e: GestureEvent) => { this.panUpdate(e); })
          .onActionEnd(() => { this.panEnd(); })
      )
    )

    // 右上角状态圈
    .overlay(this.checkDot(t), { align: Alignment.TopEnd, offset: { x: -9, y: 10 } })
    // 记住卡片在屏幕上的位置，长按时浮动卡片从这里冒出来
    .onAreaChange((oldArea: Area, newArea: Area) => { this.cardAreas.set(t.id, newArea); })
  }

  /** 状态圈：待办=白色空心圈，进行中=半色，已完成=全色打勾 */
  @Builder checkDot(t: Task) {
    StatusDot({
      status: t.status,
      dotSize: 20,
      onTap: () => { this.cycleStatus(t); }
    })
  }

  @Builder col(status: string, label: string, dot: string) {
    Column() {
      Row({ space: 7 }) {
        Row().width(6).height(6).borderRadius(3).backgroundColor(dot)
        Text(label).fontSize(11).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#6A7F92', 1))
        Blank()
        Text(status === 'todo' ? `${this.cTodo}` : (status === 'doing' ? `${this.cDoing}` : `${this.cDone}`))
          .fontSize(9).fontColor(tk(this.dark, 'textHint'))
      }
      .width('100%')
      .padding({ left: 5, right: 5, top: 2, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      ForEach(this.byStatus(status), (t: Task) => {
        this.boardCard(t)
      }, (t: Task) => `col-${status}-${t.id}-${t.status}-${this.tick}`)

      if (status === 'todo' ? this.cTodo === 0 : (status === 'doing' ? this.cDoing === 0 : this.cDone === 0)) {
        // v4.4：每列空态说清楚「这一列是干嘛的」，跟网页版口径一致
        Text(status === 'todo' ? '把想到的事记到这里' : (status === 'doing' ? '正在做的，拖到这里' : '做完的，会落在这里'))
          .fontSize(S.tinySize)
          .fontColor(tk(this.dark, 'textPale'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 22, bottom: 22 })
      }

      Row({ space: 4 }) {
        SymbolGlyph(sym('plus')).fontSize(14).fontColor([tc(this.dark, '#A8B8C6', 1)])
        Text(`添加${label}任务`).fontSize(S.tinySize).fontColor(tk(this.dark, 'textHint'))
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .borderRadius(12)
      .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F0F8', 2), 2), style: BorderStyle.Dashed })
      .margin({ top: 8 })
      .onClick(() => {
        this.editingId = -1;
        this.addStatus = status;
        this.openSheet();
      })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 2, bottom: 12 })
    .borderRadius(18)
    .backgroundColor(tc(this.dark, '#FDFEFF', 0))
    .border({ width: 1, color: tk(this.dark, 'cardBorder') })
    .margin({ top: 10 })
  }

  /** v4.8：宽屏看板的一列 —— 外层占 1/3，内层沿用竖排版式 */
  @Builder colBox(status: string, label: string, dot: string) {
    Column() {
      this.col(status, label, dot)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 拖拽遮罩层：三个状态落点，拖到哪个就改成哪个 */
  @Builder dragOverlay() {
    Stack() {
      // 背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(16,38,58,0.55)')
        .onClick(() => { this.endDrag(); })

      Column({ space: 10 }) {
        Text('把它放到…')
          .fontSize(11)
          .fontColor(tc(this.dark, '#D3E3EF', 1))
        Row({ space: 10 }) {
          this.dropBtn('todo', '待办', '#1A6499')
          this.dropBtn('doing', '进行中', '#8A5A0F')
          this.dropBtn('done', '完成', '#12706B')
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({ left: 20, right: 20 })
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: 96 })

      // v4.2：被按住的那张卡片浮起来，跟手指走
      Column({ space: 3 }) {
        Text(this.dragTitle)
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(tc(this.dark, '#2C4257', 1))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.dragTarget.length > 0 ? `松手放到「${this.targetLabel(this.dragTarget)}」` : '拖到下面选一个状态')
          .fontSize(9)
          .fontColor(tc(this.dark, '#8FA2B3', 1))
          .width('100%')
      }
      .width(200)
      .padding({ left: 13, right: 13, top: 9, bottom: 9 })
      .borderRadius(13)
      .backgroundColor(tc(this.dark, '#FFFFFF', 0))
      .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F0F8', 2), 2) })
      .shadow({ radius: 24, color: 'rgba(16,38,58,0.32)', offsetX: 0, offsetY: 12 })
      .position({ x: this.dragX - 100, y: this.dragY - 74 })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .zIndex(50)
    .gesture(
      PanGesture({ distance: 6 })
        .onActionUpdate((e: GestureEvent) => { this.panUpdate(e); })
        .onActionEnd(() => { this.panEnd(); })
    )
  }

  @Builder dropBtn(status: string, label: string, color: string) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(12.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dragTarget === status ? onFill(this.dark) : tc(this.dark, '#E7F0F7', 1))
      Text(this.statusHint(status))
        .fontSize(8.5)
        .fontColor(this.dragTarget === status ? onFill(this.dark) : tc(this.dark, '#A9C0D2', 1))
    }
    .layoutWeight(1)
    .height(58)
    .borderRadius(14)
    .backgroundColor(this.dragTarget === status ? color : 'rgba(255,255,255,0.14)')
    .border({
      width: 1.5,
      color: this.dragTarget === status ? color : 'rgba(255,255,255,0.26)'
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.recordArea(status, newArea); })
    .onClick(() => {
      const id: number = this.dragId;
      const t: Task | null = this.findTaskLocal(id);
      this.endDrag();
      if (id > 0 && t !== null && t.status !== status) {
        this.applyStatus(id, status as TaskStatus, t.title);
      }
    })
  }

  @Builder sheetBody() {
    TaskSheet({
      editingId: this.editingId,
      defaultStatus: this.addStatus,
      onSaved: () => {
        const wasEdit: boolean = this.editingId > 0;
        this.closeSheet();
        this.editingId = -1;
        toast(this.getUIContext(), wasEdit ? '任务已更新' : '任务已添加');
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
      primaryText: '添加任务',
      // v4.8：原来这里有个「多选」按钮，但 App 根本没有批量功能（拖拽只能改状态），
      // 用户也说了「那个没啥用」⇒ 直接删掉，不再占位置。
      secondaryText: '',
      onPrimary: () => { this.editingId = -1; this.addStatus = 'todo'; this.openSheet(); },
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  build() {
    Stack() {

      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
            Column({ space: 0 }) {
            Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

            this.pageTop()

            // page-head
            Column({ space: 5 }) {
              Text('TASKS · 任务面板').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
              Text('所有事，都在这里。')
                .fontSize(23)
                .fontWeight(FontWeight.Bold)
                .fontColor(tk(this.dark, 'text'))
                .letterSpacing(-0.5)
              Row({ space: 0 }) {
                Text(`${this.cOpen} 件待处理 · 共 ${this.cTotal} 件`)
                  .fontSize(11).fontColor(tk(this.dark, 'textSub'))
                if (this.cOverdue > 0) {
                  Text(` · ${this.cOverdue} 件已逾期`)
                    .fontSize(11).fontColor(tc(this.dark, '#D2795C', 1))
                }
                if (this.cForever > 0) {
                  Text(` · ${this.cForever} 件长期`)
                    .fontSize(11).fontColor(tk(this.dark, 'textSub'))
                }
                Text(' · 按住卡片拖到别的列，就能改状态')
                  .fontSize(11).fontColor(tk(this.dark, 'textSub'))
              }
              .width('100%')
              .flexShrink(0)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 14, bottom: 14 })

            // v4.8：宽屏一行四个（网页版 .tstats{repeat(4,1fr)}），窄屏仍 2×2
            if (this.layoutMode >= 1) {
              Row({ space: 10 }) {
                this.tstat('#E8F2FC', '#1A6499', '待在待办', 'todo', false)
                this.tstat('#FDF4DC', '#8A5A0F', '正在做', 'doing', false)
                this.tstat('#E3F8F2', '#0F6E58', '已完成', 'done', false)
                this.tstat('#FBEDE9', '#A64B2E', '已逾期', 'overdue', true)
              }.width('100%')
            } else {
              Row({ space: 10 }) {
                this.tstat('#E8F2FC', '#1A6499', '待在待办', 'todo', false)
                this.tstat('#FDF4DC', '#8A5A0F', '正在做', 'doing', false)
              }.width('100%')
              Row({ space: 10 }) {
                this.tstat('#E3F8F2', '#0F6E58', '已完成', 'done', false)
                this.tstat('#FBEDE9', '#A64B2E', '已逾期', 'overdue', true)
              }.width('100%').margin({ top: 10 })
            }

            // filters
            Flex({ wrap: FlexWrap.Wrap }) {
              Chip({ text: '全部', active: this.area === 'all', onTap: () => { this.area = 'all'; this.recount(); } })
              ForEach(['work', 'side', 'media', 'study', 'life'], (a: string) => {
                Chip({ text: areaLabel(a), active: this.area === a, onTap: () => { this.area = a; this.recount(); } })
              }, (a: string) => `f-${a}`)
            }
            .width('100%')
            .margin({ top: 12 })

            Flex({ wrap: FlexWrap.Wrap }) {
              Chip({ text: '今天', active: this.due === 'today', onTap: () => { this.due = this.due === 'today' ? 'all' : 'today'; this.recount(); } })
              Chip({ text: '本周', active: this.due === 'week', onTap: () => { this.due = this.due === 'week' ? 'all' : 'week'; this.recount(); } })
              Chip({ text: '逾期', active: this.due === 'overdue', onTap: () => { this.due = this.due === 'overdue' ? 'all' : 'overdue'; this.recount(); } })
              Chip({ text: '长期', active: this.due === 'forever', onTap: () => { this.due = this.due === 'forever' ? 'all' : 'forever'; this.recount(); } })
            }
            .width('100%')
            .margin({ top: 6 })

            // v4.8：宽屏三列并排（网页版 .kanban{repeat(3,1fr)}），窄屏仍竖排
            if (this.layoutMode >= 2) {
              Row({ space: 10 }) {
                this.colBox('todo', '待办', '#1A6499')
                this.colBox('doing', '进行中', '#8A5A0F')
                this.colBox('done', '完成', '#12706B')
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .margin({ top: 6 })
            } else {
              Column() {
                this.col('todo', '待办', '#1A6499')
                this.col('doing', '进行中', '#8A5A0F')
                this.col('done', '完成', '#12706B')
              }
              .width('100%')
              .margin({ top: 6 })
            }

            // tasks-extra
            Column() {
              Card({ title: '最近七天收尾节奏', sub: '每天完成的任务数' }) {
                Column({ space: 2 }) {
                  if (this.last7Max() === 0) {
                    // 近七天一件都没收尾：不画七条空槽，直接给一句空态，省得看着像「全是满格」
                    Column({ space: 6 }) {
                      Text('最近七天还没有收尾的任务')
                        .fontSize(11)
                        .fontColor(tk(this.dark, 'textSub'))
                      Text('挑一件 10 分钟能做完的，先划掉它')
                        .fontSize(10)
                        .fontColor(tk(this.dark, 'textPale'))
                    }
                    .width('100%')
                    .padding({ top: 22, bottom: 22 })
                    .justifyContent(FlexAlign.Center)
                    .borderRadius(12)
                    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F0F8', 2), 2), style: BorderStyle.Dashed })
                  } else {
                    ForEach(this.last7(), (n: number, i: number) => {
                      Row({ space: 10 }) {
                        Text(this.last7Label(i))
                          .fontSize(S.tinySize)
                          .fontColor(i === 6 ? tc(this.dark, '#2FA9A3', 1) : tc(this.dark, '#93A6B6', 1))
                          .width(64)
                          .flexShrink(0)
                        Row() {
                          Row()
                            .height('100%')
                            .width(`${Math.max(n === 0 ? 0 : 8, Math.round(n / this.last7Max() * 100))}%`)
                            .borderRadius(99)
                            .linearGradient(i === 6
                              ? { angle: 90, colors: [['#1C7C74', 0], ['#12706B', 1]] }
                              : { angle: 90, colors: [['#2E8E84', 0], ['#12706B', 1]] })
                        }
                        .layoutWeight(1)
                        .height(11)
                        .borderRadius(99)
                        .backgroundColor(tc(this.dark, '#EFF7FB', 0))
                        .alignItems(VerticalAlign.Center)
                        Text(n === 0 ? '—' : `${n} 件`)
                          .fontSize(10)
                          .fontColor(n === 0 ? tc(this.dark, '#C8D8E4', 1) : tc(this.dark, '#5E7183', 1))
                          .width(34)
                          .textAlign(TextAlign.End)
                          .flexShrink(0)
                      }
                      .width('100%')
                      .padding({ left: 8, right: 6, top: 6, bottom: 6 })
                      .alignItems(VerticalAlign.Center)
                    }, (n: number, i: number) => `l7-${i}-${n}`)
                  }

                  Divider().color('#EDF4FA').strokeWidth(1).margin({ top: 6 })
                  Row({ space: 5 }) {
                    Text('这周完成').fontSize(9).fontColor(tk(this.dark, 'textHint'))
                    Text(`${this.cWeekDone}`).fontSize(11).fontColor(tc(this.dark, '#2B4055', 1)).fontWeight(FontWeight.Medium)
                    Text('件 · 近七天平均每天').fontSize(9).fontColor(tk(this.dark, 'textHint'))
                    Text(`${this.cLast7Avg.toFixed(1)}`).fontSize(11).fontColor(tc(this.dark, '#2B4055', 1)).fontWeight(FontWeight.Medium)
                    Text('件').fontSize(9).fontColor(tk(this.dark, 'textHint'))
                    Blank()
                  }
                  .width('100%')
                  .margin({ top: 8 })
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
              }
            }
            .width('100%')
            .margin({ top: 16 })

            Column() {
              Card({ title: '刚刚做完的', sub: '最近完成' }) {
                Column({ space: 7 }) {
                  if (this.recentDone().length === 0) {
                    Text('还没有完成的任务，先挑一件小的开始')
                      .fontSize(10)
                      .fontColor(tk(this.dark, 'textPale'))
                      .width('100%')
                      .textAlign(TextAlign.Center)
                      .padding({ top: 30, bottom: 30 })
                      .borderRadius(12)
                      .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F0F8', 2), 2), style: BorderStyle.Dashed })
                  } else {
                    ForEach(this.recentDone(), (t: Task) => {
                      Row({ space: 9 }) {
                        Row() {
                          // v4.23：fs14 的勾盒子 14x14vp，圆放大到 18vp 才装得下
                          SymbolGlyph(sym('check')).fontSize(14).fontColor([onFill(this.dark)])
                        }
                        .width(18)
                        .height(18)
                        .borderRadius(9)
                        .backgroundColor(tk(this.dark, 'brand'))
                        .justifyContent(FlexAlign.Center)
                        .alignItems(VerticalAlign.Center)
                        Text(t.title)
                          .fontSize(11.5)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(tc(this.dark, '#2C4257', 1))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                        Text(t.done_at !== null ? `${D.slashMd(D.parse(t.done_at))} ${D.hm(t.done_at)}` : '')
                          .fontSize(9)
                          .fontColor(tk(this.dark, 'textHint'))
                          .flexShrink(0)
                      }
                      .width('100%')
                      .padding({ left: 11, right: 11, top: 8, bottom: 8 })
                      .borderRadius(11)
                      .backgroundColor(tc(this.dark, '#F8FCFF', 0))
                      .border({ width: 1, color: tc(this.dark, tc(this.dark, '#EEF6FB', 2), 2) })
                      .alignItems(VerticalAlign.Center)
                    }, (t: Task) => `rd-${t.id}-${this.tick}`)
                  }

                  if (this.recentDone().length < 3) {
                    Column({ space: 3 }) {
                      Text('节奏是靠小事带起来的').fontSize(10).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#9FB2C2', 1))
                      Text('挑一件 10 分钟能收尾的，先划掉它').fontSize(S.tinySize).fontColor(tk(this.dark, 'textPale'))
                    }
                    .width('100%')
                    .padding({ top: 14, bottom: 14 })
                    .borderRadius(12)
                    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F0F8', 2), 2), style: BorderStyle.Dashed })
                    .alignItems(HorizontalAlign.Center)
                  }

                  Divider().color('#EDF4FA').strokeWidth(1).margin({ top: 4 })
                  Row({ space: 5 }) {
                    Text('累计完成').fontSize(9).fontColor(tk(this.dark, 'textHint'))
                    Text(`${this.cDoneAll}`)
                      .fontSize(11).fontColor(tc(this.dark, '#2B4055', 1)).fontWeight(FontWeight.Medium)
                    Text('件 · 还有').fontSize(9).fontColor(tk(this.dark, 'textHint'))
                    Text(`${this.cOpen}`).fontSize(11).fontColor(tc(this.dark, '#2B4055', 1)).fontWeight(FontWeight.Medium)
                    Text('件在路上').fontSize(9).fontColor(tk(this.dark, 'textHint'))
                    Blank()
                  }
                  .width('100%')
                  .margin({ top: 8 })
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
              }
            }
            .width('100%')
            .margin({ top: 14, bottom: S.pageBottom })
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
        .bindSheet($$this.showAdd, this.sheetContent(), {
          // v4.6：宽屏时弹层变成「全屏透明 + 居中卡片」，窄屏保持底部抽屉
          // v4.26：宽屏时给「窗口高度」这个绝对值，别写 '100%'
        //   （bindSheet 面板里百分比会被当成内容高度，面板撑不满、卡片不居中）
        // v4.26：宽屏时用 SheetSize.LARGE（面板几乎占满屏幕），窄屏还是贴底抽屉。
        //   之前写 '100%'，在 bindSheet 面板里百分比被解析成「内容高度」，
        //   面板只有 864vp（竖屏实测），卡片被顶到下半屏、遮罩也只盖住下半屏。
          height: SheetSize.FIT_CONTENT,
          dragBar: !this.wideMode(),
          showClose: false,
          backgroundColor: Color.Transparent,   // 面板透明，弹层内容自己带圆角白底
          width: '100%'
        })

        if (this.dragId > 0) {
          this.dragOverlay()
        }
      }
      .width('100%')
      .height('100%')
  

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

  private last7Sum(): number {
    let n = 0;
    for (const v of this.last7()) { n += v; }
    return n;
  }
}
