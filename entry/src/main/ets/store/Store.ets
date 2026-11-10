// entry/src/main/ets/store/Store.ets
// 全局单例状态。用 V1 兼容的「订阅 + 版本号」而不是 @ObservedV2：
// 各 View 订阅后把 @State tick +1 触发重绘，build() 里直接读 Store.I.xxx。
// 好处：不与现有 @Component（V1）混用 V2 装饰器，编译风险最低。
//
// v4.0：数据全部来自手机本地数据库（db/Repo.ets），不连任何服务器，离线照常可用。

import { Repo } from '../db/Repo';
import {
  Task, TaskStatus, EventItem, Note, Project, Review, HabitView, ReminderItem,
  TaskCreateResp, TaskPatchResp, EventCreateResp, EventPatchResp,
  NoteCreateResp, NotePatchResp, ProjectCreateResp,
  HabitsResp, HabitCreateResp, HabitLogResp, RemindersResp,
  OkResp, SettingsResp, SearchResp,
  TaskCreate, TaskUpdate, EventCreate, EventUpdate, NoteCreate, NoteUpdate,
  ProjectCreate, ReviewSave, HabitCreate, HabitLogReq, SettingsPatch, TaskEventLink
} from '../api/Types';
import { D } from '../utils/DateUtil';
import { Db } from '../db/Db';

export type Listener = () => void;

/** v4.12：重复任务做完后的「原件」——做完就不算一条真任务了
 *  （下一次已经另建了一条；这一条收走，不进已完成列、不进统计） */
export function isConsumedRepeat(t: Task): boolean {
  return t.status === 'done' && t.repeat_rule !== 'none';
}

export class Store {
  static readonly I: Store = new Store();

  tasks: Task[] = [];
  events: EventItem[] = [];
  notes: Note[] = [];
  projects: Project[] = [];
  reviews: Review[] = [];
  habits: HabitView[] = [];
  habitDays: string[] = [];
  habitToday: string = '';
  reminders: ReminderItem[] = [];
  /** v4.12：任务 ↔ 日程 关联 */
  taskEventLinks: TaskEventLink[] = [];
  /** v4.12：刚创建出来的任务 / 日程的 id（给关联用） */
  lastTaskId: number = -1;
  lastEventId: number = -1;
  settings: SettingsResp = { user_name: '', ai_base_url: '', ai_model: '', ai_key_set: false };
  links: number[] = [];

  loaded: boolean = false;
  loading: boolean = false;
  lastError: string = '';
  version: number = 0;

  private listeners: Listener[] = [];

  subscribe(fn: Listener): Listener {
    this.listeners.push(fn);
    const self = this;
    return () => {
      const i = self.listeners.indexOf(fn);
      if (i >= 0) { self.listeners.splice(i, 1); }
    };
  }

  notify(): void {
    this.version += 1;
    for (const fn of this.listeners) { fn(); }
  }

  /** 单项失败不拖死整页：每项自己 try/catch，最后统一 notify */
  async loadAll(): Promise<void> {
    this.loading = true;
    this.lastError = '';
    this.notify();
    await this.reloadTasks();
    await this.reloadEvents();
    await this.reloadNotes();
    await this.reloadProjects();
    await this.reloadReviews();
    await this.reloadHabits();
    await this.reloadReminders();
    await this.reloadTaskEventLinks();
    await this.reloadSettings();
    this.loaded = true;
    this.loading = false;
    this.notify();
  }

  async reloadTasks(): Promise<void> {
    try {
      this.tasks = await Repo.tasks();
    } catch (e) { this.fail(e); }
    this.notify();
  }

  async reloadEvents(): Promise<void> {
    try {
      this.events = await Repo.events();
    } catch (e) { this.fail(e); }
    this.notify();
  }

  async reloadNotes(): Promise<void> {
    try {
      // 含归档：记录页自己按「记录 / 归档」两个筛选看
      this.notes = await Repo.notes(true);
    } catch (e) { this.fail(e); }
    this.notify();
  }

  async reloadProjects(): Promise<void> {
    try {
      this.projects = await Repo.projects();
    } catch (e) { this.fail(e); }
    this.notify();
  }

  async reloadReviews(): Promise<void> {
    try {
      this.reviews = await Repo.reviews();
    } catch (e) { this.fail(e); }
    this.notify();
  }

  async reloadHabits(): Promise<void> {
    try {
      const r: HabitsResp = await Repo.habits();
      this.applyHabits(r);
    } catch (e) { this.fail(e); }
    this.notify();
  }

  async reloadReminders(): Promise<void> {
    try {
      const r: RemindersResp = await Repo.reminders();
      this.reminders = r.items ? r.items : [];
    } catch (e) { this.fail(e); }
    this.notify();
  }

  async reloadTaskEventLinks(): Promise<void> {
    try {
      this.taskEventLinks = await Repo.taskEventLinks();
    } catch (e) { this.taskEventLinks = []; }
    this.notify();
  }

  /** v4.12：把任务和日程关联起来 */
  async linkTaskEvent(taskId: number, eventId: number): Promise<boolean> {
    try {
      await Repo.linkTaskEvent(taskId, eventId);
      await this.reloadTaskEventLinks();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  /** v4.12：拆开任务和日程的关联 */
  async unlinkTaskEvent(taskId: number, eventId: number): Promise<boolean> {
    try {
      await Repo.unlinkTaskEvent(taskId, eventId);
      await this.reloadTaskEventLinks();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async reloadSettings(): Promise<void> {
    try {
      const r: SettingsResp = await Repo.settings();
      this.settings = r;
    } catch (e) { this.fail(e); }
    this.notify();
  }

  /** v4.8：深色模式开关（存 setting 表 + AppStorage，AppStorage 驱动界面重画） */
  async setDark(on: boolean): Promise<boolean> {
    try {
      await Db.setSetting('dark', on ? '1' : '0');
      AppStorage.set<boolean>('wb_dark', on);
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  /** v4.8：冷启动时把上次的深色设置恢复回来 */
  async restoreTheme(): Promise<void> {
    try {
      const v: string = await Db.getSetting('dark', '0');
      AppStorage.set<boolean>('wb_dark', v === '1');
    } catch (e) { AppStorage.set<boolean>('wb_dark', false); }
  }

  private applyHabits(r: HabitsResp): void {
    this.habitToday = r.today;
    this.habitDays = r.days ? r.days : [];
    this.habits = r.habits ? r.habits : [];
  }

  private fail(e: Object): void {
    const err = e as Error;
    this.lastError = err && err.message ? err.message : '出了点问题';
  }

  // ── 任务 ──
  findTask(id: number): Task | undefined {
    for (const t of this.tasks) { if (t.id === id) { return t; } }
    return undefined;
  }

  /** 乐观更新：先改本地，失败回滚（文档 §12.2） */
  async toggleTask(id: number): Promise<void> {
    const t = this.findTask(id);
    if (!t) { return; }
    const old: TaskStatus = t.status;
    t.status = old === 'done' ? 'todo' : 'done';
    this.tasks = [...this.tasks];       // V1 里靠整体替换触发刷新
    this.notify();
    try {
      const r: TaskPatchResp = await Repo.patchTask(id, { status: t.status } as TaskUpdate);
      if (r && r.task) {
        const idx = this.tasks.findIndex((x: Task) => x.id === id);
        if (idx >= 0) { this.tasks[idx] = r.task; }
      }
      if (r && r.next) { this.tasks.push(r.next); }
      this.tasks = [...this.tasks];
      // v4.4：项目的「完成占比」是按任务算的，任务状态一变就要重算，
      // 不然会出现「本周完成 +1，但百分比没变」。
      await this.reloadProjects();
    } catch (e) {
      t.status = old;
      this.tasks = [...this.tasks];
      this.fail(e);
    }
    this.notify();
  }

  /** 改成任意状态（待办 / 进行中 / 完成）。拖拽改状态、圈圈循环都走这里。 */
  async setTaskStatus(id: number, status: TaskStatus): Promise<void> {
    const t = this.findTask(id);
    if (!t || t.status === status) { return; }
    const old: TaskStatus = t.status;
    t.status = status;
    this.tasks = [...this.tasks];       // V1 里靠整体替换触发刷新
    this.notify();
    try {
      const r: TaskPatchResp = await Repo.patchTask(id, { status: status } as TaskUpdate);
      if (r && r.task) {
        const idx = this.tasks.findIndex((x: Task) => x.id === id);
        if (idx >= 0) { this.tasks[idx] = r.task; }
      }
      if (r && r.next) { this.tasks.push(r.next); }
      this.tasks = [...this.tasks];
      await this.reloadProjects();   // v4.4：同上，项目完成占比要跟着变
    } catch (e) {
      t.status = old;
      this.tasks = [...this.tasks];
      this.fail(e);
    }
    this.notify();
  }

  async addTask(body: TaskCreate): Promise<boolean> {
    try {
      const r: TaskCreateResp = await Repo.createTask(body);
      if (r && r.task) { this.lastTaskId = r.task.id; this.tasks.push(r.task); }
      this.tasks = [...this.tasks];
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async updateTask(id: number, body: TaskUpdate): Promise<boolean> {
    try {
      const r: TaskPatchResp = await Repo.patchTask(id, body);
      if (r && r.task) {
        const idx = this.tasks.findIndex((x: Task) => x.id === id);
        if (idx >= 0) { this.tasks[idx] = r.task; }
        this.tasks = [...this.tasks];
      }
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async deleteTask(id: number): Promise<boolean> {
    try {
      await Repo.deleteTask(id);
      this.tasks = this.tasks.filter((x: Task) => x.id !== id);
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  // ── 日程 ──
  async addEvent(body: EventCreate): Promise<boolean> {
    try {
      const r: EventCreateResp = await Repo.createEvent(body);
      if (r && r.event) { this.lastEventId = r.event.id; this.events.push(r.event); }
      this.events = [...this.events];
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async deleteEvent(id: number): Promise<boolean> {
    try {
      await Repo.deleteEvent(id);
      this.events = this.events.filter((x: EventItem) => x.id !== id);
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async updateEvent(id: number, body: EventUpdate): Promise<boolean> {
    try {
      const r: EventPatchResp = await Repo.patchEvent(id, body);
      if (r && r.event) {
        const idx = this.events.findIndex((x: EventItem) => x.id === id);
        if (idx >= 0) { this.events[idx] = r.event; }
        this.events = [...this.events];
      }
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  // ── 灵感 ──
  async addNote(body: NoteCreate): Promise<boolean> {
    try {
      const r: NoteCreateResp = await Repo.createNote(body);
      if (r && r.note) { this.notes.unshift(r.note); }
      this.notes = [...this.notes];
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async updateNote(id: number, body: NoteUpdate): Promise<boolean> {
    try {
      const r: NotePatchResp = await Repo.patchNote(id, body);
      if (r && r.note) {
        const idx = this.notes.findIndex((x: Note) => x.id === id);
        if (idx >= 0) { this.notes[idx] = r.note; }
        this.notes = [...this.notes];
      }
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async deleteNote(id: number): Promise<boolean> {
    try {
      await Repo.deleteNote(id);
      this.notes = this.notes.filter((x: Note) => x.id !== id);
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  // ── 项目 ──
  async addProject(body: ProjectCreate): Promise<boolean> {
    try {
      const r: ProjectCreateResp = await Repo.createProject(body);
      if (r && r.project) { this.projects.push(r.project); }
      this.projects = [...this.projects];
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  // ── 复盘 ──
  async saveReview(body: ReviewSave): Promise<boolean> {
    try {
      await Repo.saveReview(body);
      await this.reloadReviews();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  // ── 习惯 ──
  async addHabit(body: HabitCreate): Promise<boolean> {
    try {
      const r: HabitCreateResp = await Repo.createHabit(body);
      this.applyHabits(r);
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  /** 本地库直接算好状态，直接覆盖，避免前端算错 streak */
  async toggleHabit(habitId: number, date: string): Promise<boolean> {
    const body: HabitLogReq = { habit_id: habitId, date: date };
    try {
      const r: HabitLogResp = await Repo.toggleHabit(habitId, date);
      this.applyHabits(r);
      this.notify();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  // ── 设置 ──
  async saveSettings(body: SettingsPatch): Promise<boolean> {
    try {
      await Repo.patchSettings(body);
      await this.reloadSettings();
      return true;
    } catch (e) { this.fail(e); this.notify(); return false; }
  }

  async search(q: string, kind: string): Promise<SearchResp> {
    try { return await Repo.search(q, kind); }
    catch (e) { this.fail(e); return { hits: [], total: 0, counts: [0, 0, 0, 0], tasks: [], notes: [] }; }
  }

  // ── 首页统计（前端算，工作台是服务端算好传 props，这里等价）──
  get totalTasks(): number { return this.tasks.length; }
  get doneTasks(): number {
    let n = 0;
    for (const t of this.tasks) { if (t.status === 'done') { n += 1; } }
    return n;
  }
  get doingTasks(): number {
    let n = 0;
    for (const t of this.tasks) { if (t.status === 'doing') { n += 1; } }
    return n;
  }
  get todoTasks(): number {
    let n = 0;
    for (const t of this.tasks) { if (t.status === 'todo') { n += 1; } }
    return n;
  }
  get donePercent(): number {
    return this.totalTasks === 0 ? 0 : Math.round(this.doneTasks * 100 / this.totalTasks);
  }
  get todayDone(): number {
    const today = D.today();
    let n = 0;
    for (const t of this.tasks) {
      if (t.status === 'done' && t.done_at && D.dateOf(t.done_at) === today) { n += 1; }
    }
    return n;
  }
  get todayHours(): string {
    let mins = 0;
    const today = D.today();
    for (const t of this.tasks) {
      if (t.status === 'done' && t.done_at && D.dateOf(t.done_at) === today) {
        mins += t.estimate_min ? t.estimate_min : 0;
      }
    }
    return (mins / 60).toFixed(1);
  }

  /** 最近 7 天完成数，按 done_at */
  weekSeries(): number[] {
    const days = D.lastDays(7);
    const out: number[] = [];
    for (const day of days) {
      let n = 0;
      for (const t of this.tasks) {
        if (t.status === 'done' && t.done_at && D.dateOf(t.done_at) === day) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  /** 最近 30 天完成数 */
  monthSeries(): number[] {
    const days = D.lastDays(30);
    const out: number[] = [];
    for (const day of days) {
      let n = 0;
      for (const t of this.tasks) {
        if (t.status === 'done' && t.done_at && D.dateOf(t.done_at) === day) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  /** 领域占比：返回 [label, count, color] */
  /**
   * 各领域的推进情况。
   * v4.4：以前这里画的是「任务总数」（10 个待办 = 100% 进度），完全没有进度可言；
   * 网页版 stats/page.tsx 画的是完成率（done / total）。
   * 而且固定列 5 个领域（没有任务的也列出来，宽度一致），不要有的显示有的不显示。
   */
  areaStats(): AreaStat[] {
    const keys: string[] = ['work', 'side', 'media', 'study', 'life'];
    const labels: string[] = ['工作', '副业', '自媒体', '学习', '生活'];
    const colors: string[] = ['#1A6499', '#6650C8', '#A54A1E', '#14765F', '#8A5A0F'];
    const out: AreaStat[] = [];
    for (let i = 0; i < keys.length; i++) {
      let total = 0;
      let done = 0;
      for (const t of this.tasks) {
        if (t.area === keys[i]) {
          total += 1;
          if (t.status === 'done') { done += 1; }
        }
      }
      const pct: number = total === 0 ? 0 : Math.round(done * 100 / total);
      out.push({ label: labels[i], area: keys[i], total: total, done: done, pct: pct, color: colors[i] } as AreaStat);
    }
    return out;
  }

  /** 182 天热力图数据，按每天完成任务数 0–4+ */
  heatDays(): number[] {
    const days = D.lastDays(182);
    const out: number[] = [];
    for (const day of days) {
      let n = 0;
      for (const t of this.tasks) {
        if (t.status === 'done' && t.done_at && D.dateOf(t.done_at) === day) { n += 1; }
      }
      out.push(n > 4 ? 4 : n);
    }
    return out;
  }

  /** 连续活跃天数（有完成记录就算） */
  activeStreak(): number {
    // v4.4：连续天数不该被「近半年」的窗口卡住 —— 半年以上没断也该继续数
    const days = D.lastDays(400);
    let streak = 0;
    for (let i = days.length - 1; i >= 0; i--) {
      let n = 0;
      for (const t of this.tasks) {
        if (t.status === 'done' && t.done_at && D.dateOf(t.done_at) === days[i]) { n += 1; }
      }
      if (n > 0) { streak += 1; }
      else if (i !== days.length - 1) { break; }   // 今天没完成不打断
    }
    return streak;
  }
}

export interface AreaStat {
  label: string;
  area: string;
  total: number;
  done: number;
  pct: number;
  color: string;
}
