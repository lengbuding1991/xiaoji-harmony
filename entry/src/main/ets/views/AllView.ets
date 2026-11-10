// 全部内容 —— 一处看全所有东西（v3.0）
//
// 用户诉求（m12841）：任务、灵感、日程、项目、复盘、习惯…… 都要有「查看全部」的地方，
// 而且每条要带日期、按**固定规则**排序（不能随心情乱跳）。
//
// 固定排序规则（写死在这里，页面顶部会显示当前生效的那一条）：
//   任务   按「到期日 → 排期开始日 → 创建日」升序；**已完成的沉底**（组内按完成时间倒序）
//   灵感   按「最后修改时间」倒序（新的在前）
//   日程   按「开始时间」升序（快到的在前）；**已经过期的沉底**
//   项目   按「目标日期 → 创建日」升序（快到期的在前）
//   复盘   按「复盘日期」倒序（新的在前）
//   习惯   按「sort 固定顺序」（不随时间变）
//   全部   把上面所有条目按各自主时间合到一起，倒序（新的在上）；已完成的任务仍然沉底
// 顶部「⇅」一键切换升降序，规则文字跟着变；点条目跳到对应模块。
import { Store, isConsumedRepeat } from '../store/Store';
import { C, S, tk, tc } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { Chip } from '../components/Widgets';
import { TopBar } from '../components/TopBar';
import { sym } from '../components/Icon';
import { Task, Note, EventItem, Project, Review, HabitView } from '../api/Types';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

interface AllItem {
  key: string;
  kind: string;
  kindLabel: string;
  title: string;
  sub: string;
  dateText: string;
  stamp: string;
  icon: string;
  color: string;
  bg: string;
  target: string;
  done: boolean;
}

interface KindDef {
  key: string;
  label: string;
  icon: string;
  color: string;
  bg: string;
  asc: boolean;          // 该类型的默认方向：true = 升序（早的在前）
}

// v4.21：color 是压在同色浅底上的文字/图标色，全部按「对各自 bg 取 >=4.55:1」重算过
// （原来是 #3AC8C2 这类亮色，在浅底上只有 1.5~2.4:1，AGC 判色彩不通过）
const KINDS: KindDef[] = [
  { key: 'all', label: '全部', icon: 'grid', color: '#237A76', bg: '#E1F7F5', asc: false },
  { key: 'task', label: '任务', icon: 'tasks', color: '#3D729F', bg: '#EAF3FD', asc: true },
  { key: 'note', label: '灵感', icon: 'note', color: '#7360AD', bg: '#F3EEFE', asc: false },
  { key: 'event', label: '日程', icon: 'calendar', color: '#925C73', bg: '#FDEBF3', asc: true },
  { key: 'project', label: '项目', icon: 'folder', color: '#876B2D', bg: '#FDF3DC', asc: true },
  { key: 'review', label: '复盘', icon: 'undo', color: '#985E4B', bg: '#FBEDE9', asc: false },
  { key: 'habit', label: '习惯', icon: 'flame', color: '#3F796C', bg: '#E6F8F2', asc: true }
];

@Component
export struct AllView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tick: number = 0;
  @State tasks: Task[] = [];
  @State notes: Note[] = [];
  @State events: EventItem[] = [];
  @State projects: Project[] = [];
  @State reviews: Review[] = [];
  @State habits: HabitView[] = [];
  @State kind: string = 'all';
  @State asc: boolean = false;
  // 当前分类排好序的条目。排序是 O(n²) 的冒泡，所以**只在数据/分类/方向变化时重算一次**，
  // 不要在 build() 里反复调 items()。
  @State rows: AllItem[] = [];
  @State totalRows: number = 0;
  onNavigate: (page: string) => void = () => {};
  private unsub: () => void = () => {};

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  private syncStore(): void {
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.events = Store.I.events;
    this.projects = Store.I.projects;
    this.reviews = Store.I.reviews;
    this.habits = Store.I.habits;
    this.rebuild();
  }

  /** 重算当前分类的条目（数据 / 分类 / 排序方向变了才调） */
  private rebuild(): void {
    // v4.4：一次把全部条目都渲染出来，数据一多就卡。
    // 这里先截到 200 条，并在页面上说明「只显示前 N 条」。
    const all: AllItem[] = this.buildRows();
    this.totalRows = all.length;
    this.rows = all.length > 200 ? all.slice(0, 200) : all;
  }

  // ── 分类 ──────────────────────────────────────────────
  private kindDef(): KindDef {
    for (const k of KINDS) {
      if (k.key === this.kind) { return k; }
    }
    return KINDS[0];
  }

  private switchKind(key: string): void {
    if (this.kind === key) { return; }
    this.kind = key;
    for (const k of KINDS) {
      if (k.key === key) { this.asc = k.asc; }
    }
    this.rebuild();
  }

  private toggleDir(): void {
    this.asc = !this.asc;
    this.rebuild();
  }

  private countOf(key: string): number {
    if (key === 'task') { return this.tasks.length; }
    if (key === 'note') { return this.notes.length; }
    if (key === 'event') { return this.events.length; }
    if (key === 'project') { return this.projects.length; }
    if (key === 'review') { return this.reviews.length; }
    if (key === 'habit') { return this.habits.length; }
    return this.allCount();
  }

  private allCount(): number {
    return this.tasks.length + this.notes.length + this.events.length
      + this.projects.length + this.reviews.length + this.habits.length;
  }

  /** 顶部显示的排序规则说明（跟着当前类型和方向走） */
  private ruleText(): string {
    if (this.kind === 'all') {
      return this.asc ? '按主时间升序 · 早的在上' : '按主时间倒序 · 新的在上';
    }
    if (this.kind === 'task') {
      return this.asc ? '按到期日升序 · 最早到期的在前' : '按到期日倒序 · 最晚到期的在前';
    }
    if (this.kind === 'note') {
      return this.asc ? '按最后修改升序 · 旧的在前' : '按最后修改倒序 · 新的在前';
    }
    if (this.kind === 'event') {
      return this.asc ? '按开始时间升序 · 快到的在前' : '按开始时间倒序 · 远到的在前';
    }
    if (this.kind === 'project') {
      return this.asc ? '按目标日升序 · 快到期的在前' : '按目标日倒序 · 远到期的在前';
    }
    if (this.kind === 'review') {
      return this.asc ? '按日期升序 · 旧的在前' : '按日期倒序 · 新的在前';
    }
    return '按固定顺序 · 不随时间变';
  }

  private dirText(): string {
    if (this.kind === 'habit') { return '固定顺序'; }
    return this.asc ? '旧 → 新' : '新 → 旧';
  }

  // ── 日期 ──────────────────────────────────────────────
  /** 统一的日期显示：今天/明天/昨天/N 天后/N 天前/MM/DD HH:mm */
  private dateLabel(s: string): string {
    if (s === null || s.length < 10) { return '—'; }
    // v4.4：没有日期的条目以前显示「9999/12/31」，很难看
    if (s.startsWith('9999')) { return '—'; }
    const day: string = s.slice(0, 10);
    const time: string = s.length >= 16 ? s.slice(11, 16) : '';
    const diff: number = D.diffDays(D.parse(day), new Date());   // 未来为正
    if (diff === 0) { return time.length > 0 ? `今天 ${time}` : '今天'; }
    if (diff === 1) { return time.length > 0 ? `明天 ${time}` : '明天'; }
    if (diff === -1) { return time.length > 0 ? `昨天 ${time}` : '昨天'; }
    if (diff > 1 && diff < 7) { return `${diff} 天后`; }
    if (diff < -1 && diff > -7) { return `${-diff} 天前`; }
    const mo: number = Number(day.slice(5, 7));
    const da: number = Number(day.slice(8, 10));
    const md: string = `${mo}/${da}`;
    if (time.length > 0) { return `${md} ${time}`; }
    return md;
  }

  // ── 各类型条目 ────────────────────────────────────────
  /**
   * 任务的主时间。
   * v4.4：① 纯日期不要拼 'T00:00' —— 拼了就会显示成「今天 00:00」；
   * ② 已完成的任务用**完成时间**（页面承诺「已完成的沉底（按完成时间倒序）」，
   * 以前按到期日排，跟承诺对不上）；③ 「全部」这个混合视图里，
   * 任务要用创建时间，否则「未来到期的任务」和「上周写的记录」会混在同一根时间轴上。
   */
  private taskStamp(t: Task, mixed: boolean = false): string {
    if (t.status === 'done' && t.done_at !== null && t.done_at.length > 0) { return t.done_at; }
    if (mixed) {
      if (t.created_at !== null && t.created_at.length > 0) { return t.created_at; }
      if (t.updated_at !== null && t.updated_at.length > 0) { return t.updated_at; }
    }
    if (t.due_date !== null && t.due_date.length > 0) { return t.due_date; }
    if (t.scheduled_start !== null && t.scheduled_start.length > 0) { return t.scheduled_start; }
    if (t.created_at !== null && t.created_at.length > 0) { return t.created_at; }
    return '9999-12-31T00:00';
  }

  private statusLabel(s: string): string {
    if (s === 'done') { return '已完成'; }
    if (s === 'doing') { return '进行中'; }
    return '待办';
  }

  private taskItems(mixed: boolean = false): AllItem[] {
    const out: AllItem[] = [];
    for (const t of this.tasks) {
      const stamp: string = this.taskStamp(t, mixed);
      const done: boolean = t.status === 'done';
      let sub: string = `${this.statusLabel(t.status)}`;
      if (t.due_date !== null && t.due_date.length > 0) {
        sub += ` · 截止 ${D.md(t.due_date)}`;
      }
      if (t.project !== null && t.project.length > 0) {
        sub += ` · ${t.project}`;
      } else if (t.priority === 'high') {
        sub += ' · 要紧';
      }
      // v4.12：重复任务做完的「原件」：还在这儿，但标出来（已收走、不计统计）
      if (isConsumedRepeat(t)) {
        sub += ' · 已消耗';
      }
      out.push({
        key: `t-${t.id}`, kind: 'task', kindLabel: '任务', title: t.title,
        sub: sub, dateText: this.dateLabel(stamp), stamp: stamp,
        icon: 'tasks', color: '#3D729F', bg: '#EAF3FD', target: 'tasks', done: done
      } as AllItem);
    }
    return this.orderTasks(out);
  }

  private noteStamp(n: Note): string {
    if (n.updated_at !== null && n.updated_at.length > 0) { return n.updated_at; }
    if (n.created_at !== null && n.created_at.length > 0) { return n.created_at; }
    return '9999-12-31T00:00';
  }

  private noteItems(): AllItem[] {
    const out: AllItem[] = [];
    // v4.4：置顶的排前面（记录页就是这个规矩，见 views/NotesView.ets）
    const notes: Note[] = this.notes.slice(0);
    for (let i = 0; i < notes.length; i++) {
      for (let j = i + 1; j < notes.length; j++) {
        if (notes[j].pinned > notes[i].pinned) {
          const tmp: Note = notes[i];
          notes[i] = notes[j];
          notes[j] = tmp;
        }
      }
    }
    for (const n of notes) {
      const stamp: string = this.noteStamp(n);
      let sub: string = n.source !== null && n.source.length > 0 ? n.source : '记录灵感';
      if (n.archived === 1) { sub += ' · 已归档'; }
      if (n.pinned === 1) { sub += ' · 置顶'; }
      const title: string = n.title !== null && n.title.trim().length > 0
        ? n.title.trim() : (n.content !== null && n.content.trim().length > 0 ? n.content.trim().substring(0, 18) : '（无标题）');
      out.push({
        key: `n-${n.id}`, kind: 'note', kindLabel: '灵感', title: title,
        sub: sub, dateText: this.dateLabel(stamp), stamp: stamp,
        icon: 'note', color: '#7360AD', bg: '#F3EEFE', target: 'notes', done: false
      } as AllItem);
    }
    return this.sortByStamp(out);
  }

  private eventItems(): AllItem[] {
    const out: AllItem[] = [];
    const now: number = Date.now();
    for (const e of this.events) {
      const stamp: string = e.start_at !== null && e.start_at.length > 0 ? e.start_at : e.created_at;
      const when: string = e.all_day === 1 ? '全天' : D.hm(e.start_at);
      let sub: string = when;
      if (e.location !== null && e.location.length > 0) { sub += ` · ${e.location}`; }
      const past: boolean = D.parse(stamp).getTime() < now;
      out.push({
        key: `e-${e.id}`, kind: 'event', kindLabel: '日程', title: e.title,
        sub: sub, dateText: this.dateLabel(stamp), stamp: stamp,
        icon: 'calendar', color: '#925C73', bg: '#FDEBF3', target: 'calendar', done: past
      } as AllItem);
    }
    return this.orderEvents(out);
  }

  private projectItems(): AllItem[] {
    const out: AllItem[] = [];
    for (const p of this.projects) {
      const stamp: string = p.target_date !== null && p.target_date.length > 0
        ? p.target_date : p.created_at;
      let sub: string = p.status !== null && p.status.length > 0 ? p.status : '进行中';
      if (p.total > 0) { sub += ` · ${p.done}/${p.total} 项完成`; }
      out.push({
        key: `p-${p.id}`, kind: 'project', kindLabel: '项目', title: p.name,
        sub: sub, dateText: this.dateLabel(stamp), stamp: stamp,
        icon: 'folder', color: '#876B2D', bg: '#FDF3DC', target: 'projects', done: false
      } as AllItem);
    }
    return this.sortByStamp(out);
  }

  private reviewItems(): AllItem[] {
    const out: AllItem[] = [];
    for (const r of this.reviews) {
      const stamp: string = r.date;
      let sub: string = r.type === 'weekly' ? '周复盘' : '日复盘';
      if (r.summary !== null && r.summary.length > 0) {
        sub += ` · ${r.summary}`;
      } else if (r.did !== null && r.did.length > 0) {
        sub += ` · ${r.did}`;
      }
      out.push({
        key: `r-${r.id}`, kind: 'review', kindLabel: '复盘', title: r.date,
        sub: sub, dateText: this.dateLabel(stamp), stamp: stamp,
        icon: 'doc', color: '#985E4B', bg: '#FBEDE9', target: 'review', done: false
      } as AllItem);
    }
    return this.sortByStamp(out);
  }

  private habitItems(): AllItem[] {
    const out: AllItem[] = [];
    const list: HabitView[] = this.habits.slice(0);
    // 固定顺序：sort 小的在前；一样就按创建时间
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        const a: HabitView = list[i];
        const b: HabitView = list[j];
        const swap: boolean = b.sort < a.sort
          || (b.sort === a.sort && b.created_at < a.created_at);
        if (swap) { list[i] = b; list[j] = a; }
      }
    }
    for (const h of list) {
      let sub: string = h.archived === 1 ? '已归档' : '每日打卡';
      if (h.streak > 0) { sub += ` · 连续 ${h.streak} 天`; }
      out.push({
        key: `h-${h.id}`, kind: 'habit', kindLabel: '习惯', title: h.name,
        sub: sub, dateText: this.dateLabel(h.created_at), stamp: h.created_at,
        icon: 'flame', color: '#3F796C', bg: '#E6F8F2', target: 'habits', done: false
      } as AllItem);
    }
    return out;
  }

  // ── 排序 ──────────────────────────────────────────────
  /** 按 stamp 字符串（yyyy-MM-ddTHH:mm）升降序；forceDesc=true 时强制倒序（沉底的那一组用） */
  private sortByStamp(list: AllItem[], forceDesc: boolean = false): AllItem[] {
    const out: AllItem[] = list.slice(0);
    const desc: boolean = forceDesc ? true : !this.asc;
    for (let i = 0; i < out.length; i++) {
      for (let j = i + 1; j < out.length; j++) {
        const swap: boolean = desc ? out[j].stamp > out[i].stamp : out[j].stamp < out[i].stamp;
        if (swap) {
          const tmp: AllItem = out[i];
          out[i] = out[j];
          out[j] = tmp;
        }
      }
    }
    return out;
  }

  /** 任务：未完成在前（按时间升/降序），已完成的沉底（组内按完成时间倒序） */
  private orderTasks(list: AllItem[]): AllItem[] {
    const open: AllItem[] = [];
    const done: AllItem[] = [];
    for (const it of list) {
      if (it.done) { done.push(it); } else { open.push(it); }
    }
    const a: AllItem[] = this.sortByStamp(open);
    const b: AllItem[] = this.sortByStamp(done, true);
    return a.concat(b);
  }

  /** 日程：没过期的在前（按开始时间），过期的沉底（组内倒序：最近过期的在前） */
  private orderEvents(list: AllItem[]): AllItem[] {
    const future: AllItem[] = [];
    const past: AllItem[] = [];
    for (const it of list) {
      if (it.done) { past.push(it); } else { future.push(it); }
    }
    const a: AllItem[] = this.sortByStamp(future);
    const b: AllItem[] = this.sortByStamp(past, true);
    return a.concat(b);
  }

  /** 当前分类的条目 */
  private buildRows(): AllItem[] {
    if (this.kind === 'task') { return this.taskItems(); }
    if (this.kind === 'note') { return this.noteItems(); }
    if (this.kind === 'event') { return this.eventItems(); }
    if (this.kind === 'project') { return this.projectItems(); }
    if (this.kind === 'review') { return this.reviewItems(); }
    if (this.kind === 'habit') { return this.habitItems(); }
    // 全部：合并所有类型
    const merged: AllItem[] = [];
    // v4.4：「全部」是混合时间轴，任务用创建时间，不能用未来的到期日
    for (const t of this.taskItems(true)) { merged.push(t); }
    for (const n of this.noteItems()) { merged.push(n); }
    for (const e of this.eventItems()) { merged.push(e); }
    for (const p of this.projectItems()) { merged.push(p); }
    for (const r of this.reviewItems()) { merged.push(r); }
    for (const h of this.habitItems()) { merged.push(h); }
    const sorted: AllItem[] = this.sortByStamp(merged);
    // 已完成的任务沉底（其余类型保持时间顺序）
    const live: AllItem[] = [];
    const fin: AllItem[] = [];
    for (const it of sorted) {
      if (it.done && it.kind === 'task') { fin.push(it); } else { live.push(it); }
    }
    return live.concat(fin);
  }

  private emptyText(): string {
    if (this.kind === 'task') { return '还没有任务。'; }
    if (this.kind === 'note') { return '还没有记录。'; }
    if (this.kind === 'event') { return '还没有日程。'; }
    if (this.kind === 'project') { return '还没有项目。'; }
    if (this.kind === 'review') { return '还没有复盘。'; }
    if (this.kind === 'habit') { return '还没有习惯。'; }
    return '这里还是空的，先去记一条吧。';
  }

  // ── 视图 ──────────────────────────────────────────────
  @Builder row(it: AllItem) {
    Row({ space: 9 }) {
      Row() {
        SymbolGlyph(sym(it.icon)).fontSize(14).fontColor([it.color])
      }
      .width(30)
      .height(30)
      .borderRadius(10)
      .backgroundColor(it.bg)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 3 }) {
        Row({ space: 5 }) {
          Text(it.kindLabel)
            .fontSize(8.5)
            .fontColor(it.color)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor(it.bg)
          Text(it.title)
            .fontSize(12)
            .fontColor(tk(this.dark, 'text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(it.sub)
          .fontSize(9.5)
          .fontColor(tk(this.dark, 'textHint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(it.dateText)
        .fontSize(9.5)
        .fontColor(tk(this.dark, 'textFaint'))
        .maxLines(1)
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
    .border({ width: { bottom: 1 }, color: tc(this.dark, '#F2F7FB', 2) })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onNavigate(it.target); })
  }

  @Builder pageTop() {
    TopBar({
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  build() {
    Scroll() {
      Column() {
        Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

        this.pageTop()

        // page-head
        Column({ space: 5 }) {
          Text('ALL · 全部内容')
            .fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
          Text('所有东西，都在这儿。')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
          Text('任务、灵感、日程、项目、复盘、习惯，一处看全，每条都带日期。')
            .fontSize(11).fontColor(tk(this.dark, 'textSub'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14, bottom: 12 })

        // 分类切换
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(KINDS, (k: KindDef) => {
            Chip({
              text: `${k.label} ${this.countOf(k.key)}`,
              active: this.kind === k.key,
              onTap: () => { this.switchKind(k.key); }
            })
          }, (k: KindDef) => `ak-${k.key}`)
        }
        .width('100%')
        .margin({ bottom: 10 })

        // 排序说明 + 切换
        Row({ space: 8 }) {
          Text(this.ruleText())
            .fontSize(9.5)
            .fontColor(tk(this.dark, 'textHint'))
            .layoutWeight(1)
            .maxLines(2)
          // v4.7：习惯是固定顺序，排序按钮点了没反应（死控件）—— 干脆不显示
          if (this.kind !== 'habit') {
            Row({ space: 4 }) {
              SymbolGlyph(sym('undo')).fontSize(14).fontColor([tk(this.dark, 'textSub')])
              Text(this.dirText())
                .fontSize(9.5)
                .fontColor(tc(this.dark, '#5E7183', 1))
            }
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(999)
            .backgroundColor(tk(this.dark, 'card'))
            .border({ width: 1, color: tk(this.dark, 'line') })
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.toggleDir(); })
          }
        }
        .width('100%')
        .margin({ bottom: 10 })

        // 列表
        Card({
          title: this.kindDef().label,
          sub: this.totalRows > this.rows.length
            ? `显示 ${this.rows.length} / ${this.totalRows} 条（只显示前 200 条）`
            : `${this.rows.length} 条`,
          bodyPadTop: 4, bodyPadBottom: 8
        }) {
          Column({ space: 0 }) {
            if (this.rows.length === 0) {
              Column({ space: 5 }) {
                Text(this.emptyText())
                  .fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5E7183', 1))
                Text('换个分类看看，或者回到首页记一条。')
                  .fontSize(10.5).fontColor(tc(this.dark, '#A8B8C6', 1))
              }
              .width('100%')
              .padding({ top: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.rows, (it: AllItem) => {
                this.row(it)
              }, (it: AllItem) => `al-${it.key}-${it.stamp}-${this.tick}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        Text('点任意一条，跳到对应的地方。')
          .fontSize(9).fontColor(tc(this.dark, '#B7C7D4', 1))
          .width('100%')
          .padding({ top: 12, bottom: 4 })
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
  }
}
