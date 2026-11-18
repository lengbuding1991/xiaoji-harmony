// 随手记
// 逐块对齐「个人工作台」components/NotesApp.tsx 的手机端：
//   eyebrow「NOTES · 随手记」→ h1「先记下来，再慢慢整理。」→「N 条记录 · 手动保存」
//   → 右侧 记录/归档 两个 chip
//   → 左栏：搜索框 + 记录列表（置顶/标题/摘要/来源·时间·标签）
//          + 「随手记一句」虚线卡（4 个种子 + 空白记录）+ 底部统计（本月/标签数/进度条/本周/spark/标签）
//   → 右栏：‹ 全部记录 + 置顶/归档/删除/保存(右上角) + 标题 + 来源·时间·已保存 + 来源胶囊 + 编辑/预览 + 正文 + 关联
// 手机端列表与编辑器是两块屏（mEditing），与工作台的 .notes-grid.m-edit/.m-list 一致。
import { Store } from '../store/Store';
import { onFill, S, sheetShadow, tc, tk, tkInk } from '../utils/Theme';
import { R } from '../utils/Responsive';
import { D } from '../utils/DateUtil';
import { Chip } from '../components/Widgets';
import { FormErr } from '../components/FormKit';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { Repo } from '../db/Repo';
import {
  Note, NoteCreate, NoteUpdate, NoteLinksResp, NoteLink, TaskCreate, Task
} from '../api/Types';
import { TopBar } from '../components/TopBar';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';
import { EditorBus } from '../utils/EditorBus';

const SOURCES: string[] = ['灵感', '工作', '学习', '复盘'];
const SEEDS: string[] = ['今天的收获', '一个想法', '待办清单', '复盘素材'];

interface NotePatchBox {
  source?: string;
}

@Component
export struct NotesView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  // v5.17：宽屏列数（>1180vp 三列 / >820vp 两列 / 更窄一列）。
  //   R.cols() 读的是 AppStorage，改窗口大小时不会自己触发本页重画 ⇒ 这里挂一个 @StorageLink，
  //   窗口宽度一变（旋转、分屏、拖窗口）本页就会重画，栅格列数跟着变。
  @StorageLink('wb_cols') cols: number = 1;
  @State tick: number = 0;
  @State notes: Note[] = [];
  // v4.5：ArkUI V1 只刷新「表达式里直接读过 state」的节点 ⇒ 所有计数进 @State
  @State kLive: number = 0;
  @State kMonth: number = 0;
  @State kWeek: number = 0;
  @State kTags: number = 0;
  @State kList: number = 0;
  @State kWeekSeries: number[] = [];
  @State tasks: Task[] = [];
  @State q: string = '';
  @State tagFilter: string = '';
  @State activeId: number = -1;
  @State showArchived: boolean = false;
  /** 手机上：false = 列表，true = 编辑这条 */
  // v4.4：编辑器改成居中弹窗后，外层（pages/Index.ets）需要知道「弹窗开着没」，
  // 好在弹窗打开时把底部导航藏起来、返回键先关弹窗 ⇒ 用 AppStorage 当通道。
  @StorageLink('wb_note_editor_open') mEditing: boolean = false;

  @State editTitle: string = '';
  @State editBody: string = '';
  @State editTags: string = '';
  @State editSource: string = '灵感';
  @State preview: boolean = false;
  @State savedAt: string = '';
  @State saving: boolean = false;

  @State showNew: boolean = false;
  onLogout: () => void = () => {};
  @State newErr: string = '';
  @State newTitle: string = '';
  @State busy: boolean = false;

  /** 删除后的撤销条 */
  @State undoId: number = -1;
  @State undoTitle: string = '';
  @State undoTags: string = '';
  @State undoSource: string = '灵感';
  @State undoBody: string = '';

  @State links: NoteLink[] = [];
  @State linkBusy: boolean = false;

  private unsub: () => void = () => {};

  private syncStore(): void {
    this.notes = Store.I.notes;
    this.tasks = Store.I.tasks;
    this.recalc();
  }

  /** v4.5：把界面上要显示的计数全部算好写进 @State */
  private recalc(): void {
    this.kLive = this.liveCount();
    this.kMonth = this.monthCount();
    this.kWeek = this.weekCount();
    this.kTags = this.allTags().length;
    this.kList = this.list().length;
    this.kWeekSeries = this.weekSeries();
  }

  /**
   * v5.17 宽屏两栏：栅格总列数。
   * 断点跟网页端 .home-grid 一致（>1180px 三列 / ≤1180px 两列 / ≤820px 一列），
   * App 这边的数值就是 R.update 写进 AppStorage 的 'wb_cols'。
   */
  private gridCols(): number {
    return this.cols;
  }

  /**
   * v5.17 宽屏两栏：某个块占几列（同 HomeView 的写法）。
   * 权重 3 = 整行，权重 2 = 两列，权重 1 = 一列；手机上永远一列。
   */
  private spanFor(weight: number): number {
    const c: number = this.cols;
    if (weight >= 3 && c >= 2) { return c; }
    if (weight >= 2 && c >= 3) { return 2; }
    return 1;
  }

  onNavigate: (page: string) => void = () => {};
  /** v4.4：编辑器浮层开/关时告诉外层（外层要把底部导航藏起来） */
  onOverlay: (open: boolean) => void = () => {};

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
    // v5.14：注册「请关闭编辑器」通道。
    //   外层（pages/Index.ets）的系统返回键原来直接把 wb_note_editor_open 置 false，
    //   编辑器关了但**刚写的内容没落盘** —— 现在返回键走这条通道，由本组件自己走 closeEditor()。
    EditorBus.setHandler(() => { this.closeEditor(); });
  }

  aboutToDisappear(): void {
    this.unsub();
    EditorBus.setHandler(() => {});
    this.flushSave();
  }

  // ─────────── 数据 ───────────
  private matches(n: Note): boolean {
    if (this.showArchived) {
      if (n.archived !== 1) { return false; }
    } else if (n.archived === 1) {
      return false;
    }
    if (this.tagFilter.length > 0) {
      let hit: boolean = false;
      for (const t of n.tags.split(',')) {
        if (t.trim() === this.tagFilter) { hit = true; }
      }
      if (!hit) { return false; }
    }
    const kw: string = this.q.trim().toLowerCase();
    if (kw.length === 0) { return true; }
    const hay: string = `${n.title}\n${n.content}\n${n.tags}`.toLowerCase();
    return hay.indexOf(kw) >= 0;
  }

  private list(): Note[] {
    const out: Note[] = [];
    for (const n of this.notes) {
      if (this.matches(n)) { out.push(n); }
    }
    // 置顶优先，再按 updated_at 倒序（冒泡，ArkTS 不接受比较器）
    for (let i = 0; i < out.length; i++) {
      for (let j = i + 1; j < out.length; j++) {
        const a: number = out[i].pinned === 1 ? 1 : 0;
        const b: number = out[j].pinned === 1 ? 1 : 0;
        let swap: boolean = false;
        if (b > a) {
          swap = true;
        } else if (b === a && out[j].updated_at > out[i].updated_at) {
          swap = true;
        }
        if (swap) {
          const t = out[i];
          out[i] = out[j];
          out[j] = t;
        }
      }
    }
    return out;
  }

  private liveCount(): number {
    let n = 0;
    for (const x of this.notes) {
      if (x.archived !== 1) { n += 1; }
    }
    return n;
  }

  private monthCount(): number {
    const m: string = D.today().substring(0, 7);
    let n = 0;
    for (const x of this.notes) {
      if (x.archived === 1) { continue; }
      if (x.created_at.substring(0, 7) === m) { n += 1; }
    }
    return n;
  }

  private allTags(): string[] {
    const out: string[] = [];
    for (const n of this.notes) {
      if (n.tags.length === 0) { continue; }
      for (const t of n.tags.split(',')) {
        const s: string = t.trim();
        if (s.length > 0 && out.indexOf(s) < 0) { out.push(s); }
      }
    }
    return out;
  }

  /** 最近 7 天每天记了几条 */
  private weekSeries(): number[] {
    const out: number[] = [];
    for (let i = 6; i >= 0; i--) {
      const key: string = D.key(D.dateAdd(new Date(), -i));
      let n = 0;
      for (const x of this.notes) {
        if (x.archived === 1) { continue; }
        if (D.dateOf(x.created_at) === key) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  private weekCount(): number {
    const ws: string = D.weekStart();
    let n = 0;
    for (const x of this.notes) {
      if (x.archived === 1) { continue; }
      if (D.dateOf(x.created_at) >= ws) { n += 1; }
    }
    return n;
  }

  private weekMax(): number {
    let m = 1;
    for (const v of this.weekSeries()) {
      if (v > m) { m = v; }
    }
    return m;
  }

  private snippet(n: Note): string {
    const one: string = n.content.replace(/[#*`>\-]/g, '').replace(/\s+/g, ' ').trim();
    return one.length > 44 ? `${one.substring(0, 44)}…` : one;
  }

  private active(): Note | undefined {
    for (const n of this.notes) {
      if (n.id === this.activeId) { return n; }
    }
    return undefined;
  }

  // ─────────── 打开 / 保存 ───────────
  private open(id: number): void {
    let found: Note | undefined = undefined;
    for (const x of this.notes) {
      if (x.id === id) { found = x; }
    }
    if (found === undefined) { return; }
    this.activeId = id;
    this.editTitle = found.title;
    this.editBody = found.content;
    this.editTags = found.tags;
    this.editSource = found.source.length > 0 ? found.source : '灵感';
    this.preview = false;
    this.savedAt = '';
    this.mEditing = true;
    this.onOverlay(true);
    this.loadLinks(id);
  }

  /**
   * v4.4：关闭编辑器。
   * 手机上「点错了关掉」不该丢内容 ⇒ 有内容就先落盘再关。
   * silent = true 表示「刚保存过，别再提示一次」。
   *
   * v5.14：改成 async。
   *   原来 `flushSave()` 是「发起就返回」，**不等结果**就接着关窗口并弹「已存好」——
   *   写库失败时用户看到的是「已存好」，其实一个字都没存进去，而且窗口已经关了，
   *   连重试的机会都没有。
   *   现在：**等落库结果出来再决定关不关** —— 失败就留在编辑器里，提示「没存上，内容还在，再试一次」。
   */
  private async closeEditor(silent: boolean = false): Promise<void> {
    if (!silent) {
      const hasContent: boolean = this.editTitle.trim().length > 0 || this.editBody.trim().length > 0;
      if (hasContent) {
        const ok: boolean = await this.flushSave();
        if (!ok) {
          // 存不进去 ⇒ 不关（内容还在屏幕上，用户还能改、还能再试）
          toast(this.getUIContext(), '没存上，内容还在，再试一次');
          return;
        }
        toast(this.getUIContext(), '已存好');
      }
    }
    this.activeId = -1;
    this.mEditing = false;
    this.onOverlay(false);
    this.links = [];
  }

  /**
   * 手机上手动保存：不再做「停止输入 0.9 秒后自动保存」。
   *
   * v5.14：**改成 async 并返回 boolean**（true = 已落库或本来就没改动）。
   *   原来返回 void，调用方无从知道结果 ⇒ 只能盲目弹「存好了」。
   */
  private async flushSave(): Promise<boolean> {
    const cur: Note | undefined = this.active();
    if (cur === undefined) { return true; }
    const changed: boolean = cur.title !== this.editTitle || cur.content !== this.editBody ||
      cur.tags !== this.editTags || cur.source !== this.editSource;
    if (!changed) { return true; }
    // v4.4：落库口径统一成一条规则（跟右下角「快速记一笔」完全一样）：
    //   标题 = 正文首行前 40 字
    //   正文 = 上面大框 + 补充框的全文
    // 以前这里是「标题=大框全文 / 正文=补充框全文」，跟快速记一笔（标题=首行40字）
    // 各记各的 —— 同一段话从两个入口进库，字段含义不一样，搜索和列表就都对不齐。
    const main: string = this.editTitle.trim();
    const extra: string = this.editBody.trim();
    const full: string = extra.length > 0 ? (main.length > 0 ? `${main}\n${extra}` : extra) : main;
    const firstLine: string = full.length > 0 ? full.split('\n')[0].trim() : '';
    const title: string = firstLine.substring(0, 40);
    const content: string = full;
    const body: NoteUpdate = {
      title: title,
      content: content,
      tags: this.editTags,
      source: this.editSource
    } as NoteUpdate;
    this.saving = true;
    const ok: boolean = await Store.I.updateNote(cur.id, body);
    this.saving = false;
    if (!ok) { return false; }
    const d: Date = new Date();
    const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
    const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
    const ss: string = d.getSeconds() < 10 ? `0${d.getSeconds()}` : `${d.getSeconds()}`;
    this.savedAt = `${hh}:${mm}:${ss}`;
    return true;
  }

  /**
   * 点「保存」：写回本地库 → 存好了 → 回到记录列表。
   * v5.14：**等落库结果**。失败就留在编辑器里并说清楚，别弹「存好了」。
   */
  private async saveNow(): Promise<void> {
    const ok: boolean = await this.flushSave();
    if (!ok) {
      toast(this.getUIContext(), '没存上，内容还在，再试一次');
      return;
    }
    await this.closeEditor(true);
    toast(this.getUIContext(), '存好了');
  }

  private async createNote(seed: string, withTitle: boolean): Promise<void> {
    const title: string = withTitle ? this.newTitle.trim() : seed;
    // 工作台：已有空白记录就复用，避免连点两次留下两条空记录
    for (const n of this.notes) {
      if (n.archived === 0 && n.content.length === 0 && n.title.length === 0) {
        if (seed.length > 0 || withTitle) {
          await Store.I.updateNote(n.id, { title: title } as NoteUpdate);
        }
        this.open(n.id);
        return;
      }
    }
    const body: NoteCreate = {
      title: title,
      content: '',
      source: '灵感'
    } as NoteCreate;
    this.busy = true;
    const ok: boolean = await Store.I.addNote(body);
    this.busy = false;
    if (!ok) {
      this.newErr = Store.I.lastError.length > 0 ? Store.I.lastError : '没建起来，再试一次';
      return;
    }
    this.showNew = false;
    this.newErr = '';
    this.newTitle = '';
    // 新记录排在最前（置顶 + updated_at 最新）
    if (this.notes.length > 0) {
      this.open(this.notes[0].id);
    }
  }

  private async setSource(s: string): Promise<void> {
    this.editSource = s;
    // v5.14：等结果 —— 改来源也是一次落盘，失败要说一声（原来静默）。
    const ok: boolean = await this.flushSave();
    if (!ok) { toast(this.getUIContext(), '没存上，内容还在，再试一次'); }
  }

  private async togglePin(): Promise<void> {
    const cur: Note | undefined = this.active();
    if (cur === undefined) { return; }
    const body: NoteUpdate = { pinned: cur.pinned === 1 ? 0 : 1 } as NoteUpdate;
    const ok: boolean = await Store.I.updateNote(cur.id, body);
    toast(this.getUIContext(), ok ? (cur.pinned === 1 ? '取消置顶' : '置顶了') : '没改动成功');
  }

  private async toggleArchive(): Promise<void> {
    const cur: Note | undefined = this.active();
    if (cur === undefined) { return; }
    const body: NoteUpdate = { archived: cur.archived === 1 ? 0 : 1 } as NoteUpdate;
    const ok: boolean = await Store.I.updateNote(cur.id, body);
    if (ok) {
      toast(this.getUIContext(), cur.archived === 1 ? '移出归档' : '收进归档');
      this.closeEditor();
    } else {
      toast(this.getUIContext(), '没改动成功');
    }
  }

  private remove(): void {
    const cur: Note | undefined = this.active();
    if (cur === undefined) { return; }
    const nm: string = cur.title.length > 0 ? cur.title : '这条记录';
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '删除这条记录？', `「${nm}」会被移除，删除后无法恢复。`, '删除',
      () => { this.doRemove(); });
  }

  /** 确认之后才真的删 */
  private async doRemove(): Promise<void> {
    const cur: Note | undefined = this.active();
    if (cur === undefined) { return; }
    this.undoId = cur.id;
    this.undoTitle = cur.title;
    this.undoBody = cur.content;
    this.undoTags = cur.tags;
    this.undoSource = cur.source;
    const ok: boolean = await Store.I.deleteNote(cur.id);
    if (ok) {
      this.closeEditor();
      toast(this.getUIContext(), `已删除「${this.undoTitle.length > 0 ? this.undoTitle : '无标题'}」`);
    } else {
      this.undoId = -1;
      toast(this.getUIContext(), '没删掉，再试一次');
    }
  }

  /** 自绘确认弹窗的内容（由 utils/Confirm.ets 挂到系统级弹窗层） */
  @Builder
  confirmBuilder() {
    ConfirmDialog({
      visible: true,
      title: Confirm.opt.title,
      desc: Confirm.opt.desc,
      danger: true,
      confirmText: Confirm.opt.confirmText,
      onConfirm: () => { Confirm.confirm(this.getUIContext()); },
      onCancel: () => { Confirm.cancel(this.getUIContext()); }
    })
  }

  /** 撤销删除：按原内容重新建一条（id 会变，内容不丢） */
  private async undoDelete(): Promise<void> {
    if (this.undoId < 0) { return; }
    const body: NoteCreate = {
      title: this.undoTitle,
      content: this.undoBody,
      source: this.undoSource.length > 0 ? this.undoSource : '灵感'
    } as NoteCreate;
    const ok: boolean = await Store.I.addNote(body);
    if (ok && this.undoTags.length > 0 && this.notes.length > 0) {
      const fresh: Note = this.notes[0];
      const patch: NoteUpdate = { tags: this.undoTags } as NoteUpdate;
      await Store.I.updateNote(fresh.id, patch);
    }
    this.undoId = -1;
    this.undoTitle = '';
    this.undoBody = '';
    this.undoTags = '';
    toast(this.getUIContext(), ok ? '恢复了' : '恢复失败');
  }

  // ─────────── 关联任务 ───────────
  private async loadLinks(noteId: number): Promise<void> {
    if (noteId <= 0) { return; }
    this.linkBusy = true;
    try {
      const r: NoteLinksResp = await Repo.noteLinks(noteId);
      this.links = r.links;
    } catch (e) {
      this.links = [];
    }
    this.linkBusy = false;
  }

  private async linkTo(taskId: number): Promise<void> {
    if (this.activeId <= 0) { return; }
    interface LinkBody {
      note_id: number;
      task_id: number;
    }

    const body: LinkBody = { note_id: this.activeId, task_id: taskId } as LinkBody;
    try {
      await Repo.addLink(body.note_id, body.task_id);
      await this.loadLinks(this.activeId);
      toast(this.getUIContext(), '关联好了');
    } catch (e) {
      toast(this.getUIContext(), '关联失败，再试一次');
    }
  }

  private async unlink(taskId: number): Promise<void> {
    if (this.activeId <= 0) { return; }
    interface LinkBody {
      note_id: number;
      task_id: number;
    }

    const body: LinkBody = { note_id: this.activeId, task_id: taskId } as LinkBody;
    try {
      await Repo.removeLink(body.note_id, body.task_id);
      await this.loadLinks(this.activeId);
      toast(this.getUIContext(), '解除了');
    } catch (e) {
      toast(this.getUIContext(), '解除失败');
    }
  }

  /** 这条记录变成一件任务 */
  private async toTask(): Promise<void> {
    // v4.4：用大框 + 补充拼出来的正文（跟落库口径一致），别拿一个可能还没保存的标题
    const mainTxt: string = this.editTitle.trim();
    const extraTxt: string = this.editBody.trim();
    const merged: string = extraTxt.length > 0 ? (mainTxt.length > 0 ? `${mainTxt}\n${extraTxt}` : extraTxt) : mainTxt;
    const t: string = merged.split('\n')[0].trim().substring(0, 60);
    if (t.length === 0) {
      toast(this.getUIContext(), '先写点什么再变任务');
      return;
    }
    const body: TaskCreate = {
      title: t,
      note: `来自记录「${mainTxt.length > 0 ? mainTxt.split('\n')[0].substring(0, 20) : '无标题'}」`,
      status: 'todo',
      area: 'work',
      priority: 'med'
    } as TaskCreate;
    const ok: boolean = await Store.I.addTask(body);
    toast(this.getUIContext(), ok ? '已变成任务' : '没建成，再试一次');
  }

  /** 原生 MenuElement 菜单项是系统默认 16fp，与编辑器 9.5–10px 字不搭；改自绘 Menu 统一到 11.5fp。 */
  @Builder
  linkCandidates() {
    Menu() {
      ForEach(this.linkableTasks(), (t: Task) => {
        MenuItem({ content: t.title })
          .onClick(() => { this.linkTo(t.id); })
      }, (t: Task) => `lk-${t.id}-${this.tick}`)
      if (this.linkableTasks().length === 0) {
        MenuItem({ content: '没有可关联的任务' }).enabled(false)
      }
    }
    .font({ size: 11.5, weight: FontWeight.Normal })
    .fontColor(tc(this.pal, '#4E6C86', 1))
    .radius(12)
    .backgroundColor(tc(this.pal, '#FFFFFF', 0))
  }

  private linkableTasks(): Task[] {
    const out: Task[] = [];
    for (const t of this.tasks) {
      if (t.status === 'done') { continue; }
      let already: boolean = false;
      for (const l of this.links) {
        if (l.task_id === t.id) { already = true; }
      }
      if (already) { continue; }
      out.push(t);
      if (out.length >= 12) { break; }
    }
    return out;
  }

  // ─────────── 简易 Markdown 预览 ───────────
  private mdLines(): string[] {
    // v4.4：预览要把两段都显示出来（大框 + 补充），不然预览比实际存的少一半
    const main: string = this.editTitle.trim();
    const extra: string = this.editBody.trim();
    const body: string = extra.length > 0 ? (main.length > 0 ? `${main}\n${extra}` : extra) : main;
    if (body.length === 0) { return []; }
    return body.split('\n');
  }

  // ─────────── 子视图 ───────────
  @Builder noteRow(n: Note) {
    Column({  space: S.spaceSm  }) {
      Row({  space: S.spaceSm  }) {
        if (n.pinned === 1) {
          SymbolGlyph(sym('pin')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'brand')])
        }
        // v5.1：标题可以留空（随手记就是随手写）—— 空标题就用正文第一行顶上
        Text(this.rowTitle(n))
          .fontSize(S.labelSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(tc(this.pal, '#2C4257', 1))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (n.content.length > 0 && n.content !== n.title) {
        Text(this.snippet(n))
          .fontSize(S.subSize)
          .fontColor(tc(this.pal, '#8FA2B3', 1))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Text(`${n.source} · ${n.updated_at.substring(5, 10).replace('-', '/')} ${D.hm(n.updated_at)}${n.tags.length > 0 ? ` · ${n.tags}` : ''}`)
        .fontSize(S.microSize)
        .fontColor(tc(this.pal, '#A8B8C6', 1))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceXl, bottom: S.spaceXl  })
    .borderRadius(S.radiusBtn)
    .backgroundColor(this.activeId === n.id ? tk(this.pal, 'brandSoft') : '#00000000')
    .border({
      width: 1,
      color: this.activeId === n.id ? tk(this.pal, 'brandLine') : '#00000000'
    })
    .alignItems(HorizontalAlign.Start)
    .margin({  bottom: S.spaceXs  })
    .onClick(() => { this.open(n.id); })
    // v5.0：按压回弹
    .stateStyles({ pressed: { .scale({ x: 0.98, y: 0.98 }) } })
    .animation({ duration: 120, curve: Curve.EaseOut })
  }

  /** v5.1：列表一行显示的标题 —— 有标题用标题，没标题就用正文第一行（对齐网页端） */
  private rowTitle(n: Note): string {
    if (n.title.length > 0) { return n.title; }
    const body: string = (n.content || '').trim();
    if (body.length === 0) { return '(无标题)'; }
    const first: string = body.split('\n')[0];
    return first.length > 30 ? first.substring(0, 30) : first;
  }

  /** 「随手记一句」虚线卡 */
  @Builder hintCard() {
    Column({  space: S.spaceMd  }) {
      SymbolGlyph(sym('pen')).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#523593', 1)])
      Text('随手记一句').fontSize(S.labelSize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#5E7183', 1))
      Text('想到什么先扔进来，以后再整理。')
        .fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1)).textAlign(TextAlign.Center)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(SEEDS, (s: string) => {
          // v5.15 可访问性：种子胶囊原来只有 ~21 高 ⇒ 外层套 40 高的透明热区，胶囊本身不变
          Row() {
            Text(s)
              .fontSize(S.tinySize)
              .fontColor(tc(this.pal, '#7C93A6', 1))
              .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceMd, bottom: S.spaceMd  })
              .borderRadius(S.radiusSm)
              .backgroundColor(tc(this.pal, '#FFFFFF', 0))
              .border({ width: 1, color: tc(this.pal, tc(this.pal, '#E6F1F9', 2), 2) })
          }
          .height(40)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .margin({  right: S.spaceMd, bottom: S.spaceMd  })
          .onClick(() => { this.createNote(s, false); })
          .accessibilityText(`新建记录 ${s}`)
        }, (s: string) => `seed-${s}`)
      }
      .width('100%')
      .margin({  top: S.spaceSm  })

      // v5.15 可访问性：「+ 空白记录」原来只有 ~22 高 ⇒ 外层套 40 高的透明热区，按钮本身不变
      Row() {
        Text('+ 空白记录')
          .fontSize(S.subSize)
          .fontColor(tc(this.pal, '#6A7F92', 1))
          .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceMd, bottom: S.spaceMd  })
          .borderRadius(S.radiusSm)
          .backgroundColor(tc(this.pal, '#FFFFFF', 0))
          .border({ width: 1, color: tk(this.pal, 'line') })
      }
      .height(40)
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .margin({  top: S.spaceXs  })
      .onClick(() => { this.createNote('', false); })
      .accessibilityText('新建空白记录')
    }
    .width('100%')
    .padding({  top: S.space3Xl, bottom: S.space2Xl, left: S.spaceXl, right: S.spaceXl  })
    .borderRadius(S.radiusCard)
    .border({ width: 1, color: tc(this.pal, tc(this.pal, '#DDEBF4', 2), 2), style: BorderStyle.Dashed })
    .linearGradient({ angle: 180, colors: [['#FBFDFF', 0], ['#F6FBFE', 1]] })
    .alignItems(HorizontalAlign.Center)
  }

  /** 底部统计：本月记录 / 标签数 / 进度条 / 本周 / spark / 标签 */
  @Builder sideFoot() {
    Column({  space: S.spaceLg  }) {
      Divider().color(tk(this.pal, 'line')).strokeWidth(1)

      Row({  space: S.spaceLg  }) {
        Text('本月记录').fontSize(S.tinySize).fontColor(tc(this.pal, '#8FA2B3', 1))
        Text(`${this.kMonth}`).fontSize(S.labelSize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#2B4055', 1))
        Blank()
        Text(`${this.kTags} 个标签`).fontSize(S.tinySize).fontColor(tc(this.pal, '#8FA2B3', 1))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 进度条
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(5).borderRadius(S.radiusPill).backgroundColor(tc(this.pal, '#EEF5FA', 0))
        Row()
          .width(`${Math.min(100, this.kMonth * 8)}%`)
          .height(5)
          .borderRadius(S.radiusPill)
          .linearGradient({ angle: 90, colors: [[tk(this.pal, 'gradFrom'), 0], [tk(this.pal, 'brand'), 1]] })
      }
      .width('100%')
      .height(5)

      Row({  space: S.spaceLg  }) {
        Text('本周').fontSize(S.tinySize).fontColor(tc(this.pal, '#8FA2B3', 1))
        Text(`${this.kWeek}`).fontSize(S.labelSize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#2B4055', 1))
        Blank()
        Text('每天记一笔').fontSize(S.tinySize).fontColor(tc(this.pal, '#8FA2B3', 1))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // spark（最近 7 天）
      Row({  space: S.spaceSm  }) {
        ForEach(this.weekSeries(), (v: number, i: number) => {
          Column() {
            Blank()
            Row()
              .width('100%')
              .height(`${Math.max(8, v / this.weekMax() * 100)}%`)
              .borderRadius({ topLeft: 3, topRight: 3, bottomLeft: 2, bottomRight: 2 })
              .backgroundColor(i === 6 ? tc(this.pal, '#523593', 0) : (v > 0 ? tc(this.pal, '#7FE3D6', 0) : tc(this.pal, '#DFF3F8', 0)))
          }
          .layoutWeight(1)
          .height(34)
          .alignItems(HorizontalAlign.Start)
        }, (v: number, i: number) => `sp-${i}-${v}`)
      }
      .width('100%')
      .height(34)
      .alignItems(VerticalAlign.Bottom)

      Row() {
        Text(D.md(D.key(D.dateAdd(new Date(), -6)))).fontSize(S.microSize).fontColor(tc(this.pal, '#A8B8C6', 1))
        Blank()
        Text('今天').fontSize(S.microSize).fontColor(tc(this.pal, '#A8B8C6', 1))
      }
      .width('100%')

      if (this.kTags > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.allTags().slice(0, 6), (t: string) => {
            // v5.15 可访问性：标签胶囊原来只有 ~17 高 ⇒ 外层套 40 高的透明热区，胶囊本身不变
            Row() {
              Text(`#${t}`)
                .fontSize(S.tinySize)
                .fontColor(this.tagFilter === t ? onFill(this.pal) : tc(this.pal, '#4E6C86', 1))
                .backgroundColor(this.tagFilter === t ? tk(this.pal, 'brandDeep') : tc(this.pal, '#F2F8FD', 0))
                .border({ width: 1, color: this.tagFilter === t ? tk(this.pal, 'brandDeep') : tc(this.pal, '#E4F1FA', 2) })
                .borderRadius(S.radiusSm)
                .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
            }
            .height(40)
            .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .margin({  right: S.spaceMd, bottom: S.spaceMd  })
            .onClick(() => { this.tagFilter = this.tagFilter === t ? '' : t; this.recalc(); })
            .accessibilityText(`按标签筛选 ${t}`)
          }, (t: string) => `tg-${t}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder listPanel() {
    Column() {
      // 搜索
      Row({  space: S.spaceLg  }) {
        SymbolGlyph(sym('search')).fontSize(S.midSize).fontColor([tc(this.pal, '#A8B8C6', 1)])
        TextInput({ placeholder: '搜索记录、标签…', text: this.q })
          .fontSize(S.labelSize)
          .placeholderFont({ size: 11.5 })
          .placeholderColor(tc(this.pal, '#A8B8C6', 1))
          .fontColor(tk(this.pal, 'text'))
          .caretColor(tk(this.pal, 'brand'))
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#00000000')
          .padding(0)
          .onChange((v: string) => { this.q = v; })
      }
      .width('100%')
      .padding({  left: S.spaceXl, right: S.spaceLg  })
      .borderRadius(S.radiusBtn)
      .backgroundColor(tc(this.pal, '#F8FBFE', 0))
      .border({ width: 1, color: tk(this.pal, 'line') })
      .alignItems(VerticalAlign.Center)
      .margin({  bottom: S.spaceLg  })

      // 记录列表
      Column() {
        if (this.kList === 0) {
          Column({  space: S.spaceSm  }) {
            Text(this.showArchived ? '归档里还是空的' : '还没有记录')
              .fontSize(S.smallSize).fontColor(tc(this.pal, '#5E7183', 1))
            Text(this.showArchived ? '暂时用不上的记录可以归档。' : '想到什么，先扔进来。')
              .fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
          }
          .width('100%')
          .padding({  top: 30, bottom: 30  })
          .alignItems(HorizontalAlign.Center)
        } else if (this.gridCols() >= 2) {
          // v5.17 宽屏：网页端 .notes-grid 是「左列表 300px + 右内容」，
          //   App 这边的编辑器是**居中弹窗**（不是右栏），所以宽屏只把记录列表铺成 2~3 列，
          //   编辑器弹窗原样不动。手机（gridCols()=1）走下面的单列分支，排版跟以前一样。
          GridRow({ columns: this.gridCols(), gutter: { x: S.gapLg, y: 0 } }) {
            ForEach(this.list(), (n: Note) => {
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  this.noteRow(n)
                }
                .width('100%')
              }
            }, (n: Note) => `nr-${n.id}-${n.pinned}-${n.updated_at}-${this.tick}`)
          }
          .width('100%')
        } else {
          ForEach(this.list(), (n: Note) => {
            this.noteRow(n)
          }, (n: Note) => `nr-${n.id}-${n.pinned}-${n.updated_at}-${this.tick}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 随手记一句
      Column() {
        this.hintCard()
      }
      .width('100%')
      .margin({  top: S.spaceXl, bottom: S.spaceXl  })

      // 底部统计
      this.sideFoot()

      // 撤销条
      if (this.undoId >= 0) {
        Row({  space: S.spaceLg  }) {
          Row().width(6).height(6).borderRadius(S.radiusDot).backgroundColor(tk(this.pal, 'brand'))
          Text(`已删除「${this.undoTitle.length > 0 ? this.undoTitle : '无标题'}」`)
            .fontSize(S.subSize)
            .fontColor(tc(this.pal, '#1F6E77', 1))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          // v5.15 可访问性：「撤销」原来只有 ~18 高 ⇒ 外层套 40 高的透明热区，按钮本身不变
          Row() {
            Text('撤销')
              .fontSize(S.subSize)
              .fontColor(tkInk(this.pal, 'brandDeep'))
              .fontWeight(FontWeight.Medium)
              .padding({  left: S.spaceLg, right: S.spaceLg, top: S.spaceSm, bottom: S.spaceSm  })
              .borderRadius(S.radiusSm)
              .backgroundColor(tc(this.pal, '#FFFFFF', 0))
          }
          .height(40)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .onClick(() => { this.undoDelete(); })
          .accessibilityText('撤销删除')
        }
        .width('100%')
        .padding({  left: S.spaceXl, right: S.spaceLg, top: S.spaceLg, bottom: S.spaceLg  })
        .borderRadius(S.radiusBtn)
        .backgroundColor(tc(this.pal, '#F2FBF9', 0))
        .border({ width: 1, color: tk(this.pal, 'brandLine') })
        .alignItems(VerticalAlign.Center)
        .margin({  top: S.spaceLg  })
      }
    }
    .width('100%')
    .padding({  left: S.space3Xl, right: S.space3Xl, top: S.space3Xl, bottom: S.space3Xl  })
    .borderRadius(S.radiusCard)
    .backgroundColor(tk(this.pal, 'card'))
    .border({ width: 1, color: tk(this.pal, 'cardBorder') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder editorPanel() {
    Column() {
      // 顶部：返回 + 置顶 / 归档 / 删除 + 保存（保存按钮在右上角，v2.9）
      Row({  space: S.spaceMd  }) {
        // v5.15 可访问性：文字按钮外层撑到 40 高（里面的字和图标不变）
        Row({  space: S.spaceSm  }) {
          SymbolGlyph(sym('close')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'brandDeep')])
          Text('关闭').fontSize(S.labelSize).fontColor(tkInk(this.pal, 'brandDeep'))
        }
        .height(40)
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.closeEditor(); })
        Blank()
        // v5.15 可访问性：置顶 / 归档 / 删除原来只有 ~26×26 ⇒ 外层套 40×40 的透明热区，图标不变
        Row() {
          SymbolGlyph(sym('pin')).fontSize(S.iconSize)
            .fontColor([this.active()?.pinned === 1 ? tkInk(this.pal, 'brand') : tc(this.pal, '#C9DAE6', 1)])
            .padding(5)
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.togglePin(); })
        .accessibilityText('置顶这条记录')
        Row() {
          SymbolGlyph(sym('archive')).fontSize(S.iconSize).fontColor([tc(this.pal, '#C9DAE6', 1)])
            .padding(5)
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.toggleArchive(); })
        .accessibilityText('归档这条记录')
        Row() {
          SymbolGlyph(sym('trash')).fontSize(S.iconSize).fontColor([tc(this.pal, '#E0B4A4', 1)])
            .padding(5)
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.remove(); })
        .accessibilityText('删除这条记录')
        Text(this.saving ? '保存中…' : '保存')
          .fontSize(S.labelSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(onFill(this.pal))
          // v5.15 可访问性：「保存」按钮原来只有 23 高 ⇒ 撑到 40
          .height(40)
          .padding({  left: S.space3Xl, right: S.space3Xl  })
          .borderRadius(S.radiusSm)
          .backgroundColor(this.saving ? tc(this.pal, '#A9BECF', 0) : tk(this.pal, 'brand'))
          .margin({  left: S.spaceSm  })
          .textAlign(TextAlign.Center)
          .onClick(() => { this.saveNow(); })
          .accessibilityText('保存这条记录')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // v5.1：模型换了 —— 标题变成「可选的一句话」，正文才是主体（对齐网页端
      //   components/NotesApp.tsx：title 可留空，content 是正文，content 才算这条记录）
      TextInput({ placeholder: '给这条记录起个标题（可以留空）', text: this.editTitle })
        .fontSize(S.headSize)
        .placeholderFont({ size: 15 })
        .placeholderColor(tc(this.pal, '#A8B8C6', 1))
        .fontWeight(FontWeight.Medium)
        .fontColor(tk(this.pal, 'text'))
        .backgroundColor('#00000000')
        .padding({  left: 0, right: 0  })
        .margin({  top: S.spaceSm  })
        .onChange((v: string) => { this.editTitle = v; })

      // 来源 · 时间 · 已保存
      Row({  space: S.spaceLg  }) {
        Text(this.editSource).fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
        Text(this.active() !== undefined
          ? `${D.key(D.parse(D.dateOf(this.active()!.created_at))).replace(/-/g, '/')} ${D.hm(this.active()!.created_at)}`
          : '').fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
        if (this.savedAt.length > 0) {
          Text(this.saving ? '保存中…' : `已保存 ${this.savedAt}`).fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
        }
      }
      .width('100%')
      .margin({  top: S.spaceSm, bottom: S.spaceLg  })

      // v5.1：来源胶囊删掉了（随手记什么都能记，来源没意义）——
      //   数据库里的 source 字段还留着，老记录不受影响。
      //   这里只留「编辑 / 预览」两个切换。
      Row({  space: S.spaceMd  }) {
        Blank()
        // v5.15 可访问性：编辑 / 预览切换原来只有 ~23 高 ⇒ 外层套 40 高的透明热区，按钮本身不变
        Row() {
          Row({  space: S.spaceSm  }) {
            SymbolGlyph(sym('pen')).fontSize(S.cardTitleSize)
              .fontColor([this.preview ? tc(this.pal, '#A8B8C6', 1) : tkInk(this.pal, 'brandDeep')])
            Text('编辑').fontSize(S.tinySize)
              .fontColor(this.preview ? tc(this.pal, '#A8B8C6', 1) : tkInk(this.pal, 'brandDeep'))
          }
          .padding({  left: S.spaceLg, right: S.spaceLg, top: S.spaceSm, bottom: S.spaceSm  })
          .borderRadius(S.radiusSm)
        }
        .height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.preview = false; })
        .accessibilityText('编辑这条记录')
        Row() {
          Row({  space: S.spaceSm  }) {
            SymbolGlyph(sym('eye')).fontSize(S.cardTitleSize)
              .fontColor([this.preview ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#A8B8C6', 1)])
            Text('预览').fontSize(S.tinySize)
              .fontColor(this.preview ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#A8B8C6', 1))
          }
          .padding({  left: S.spaceLg, right: S.spaceLg, top: S.spaceSm, bottom: S.spaceSm  })
          .borderRadius(S.radiusSm)
        }
        .height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.preview = true; })
        .accessibilityText('预览这条记录')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({  bottom: S.spaceLg  })

      Divider().color('#EDF4FA').strokeWidth(1)

      // 正文 / 预览（v5.1：正文升为主体，字更大、区域更高）
      if (!this.preview) {
        Text('正文').fontSize(S.subSize).fontColor(tc(this.pal, '#8FA2B3', 1)).width('100%').margin({  top: S.spaceLg  })
        TextArea({ placeholder: '想到什么就写什么，不用整理…支持 Markdown', text: this.editBody })
          .fontSize(S.headSize)
          .placeholderFont({ size: 15 })
          .placeholderColor(tc(this.pal, '#A8B8C6', 1))
          .fontColor(tk(this.pal, 'text'))
          .caretColor(tk(this.pal, 'brand'))
          .lineHeight(24)
          .constraintSize({ minHeight: 170 })
          .backgroundColor('#00000000')
          .padding({  left: 0, right: 0, top: S.spaceMd  })
          .onChange((v: string) => { this.editBody = v; })
      } else {
        Column({  space: S.spaceMd  }) {
          if (this.editBody.trim().length === 0) {
            Text('（还没有内容）').fontSize(S.smallSize).fontColor(tc(this.pal, '#C6D4E0', 1))
          }
          ForEach(this.mdLines(), (line: string, i: number) => {
            if (line.startsWith('### ')) {
              Text(line.substring(4)).fontSize(S.midSize).fontWeight(FontWeight.Bold).fontColor(tc(this.pal, '#3A4E60', 1)).width('100%')
            } else if (line.startsWith('## ')) {
              Text(line.substring(3)).fontSize(S.headSize).fontWeight(FontWeight.Bold).fontColor(tc(this.pal, '#3A4E60', 1)).width('100%')
            } else if (line.startsWith('# ')) {
              Text(line.substring(2)).fontSize(S.sectionSize).fontWeight(FontWeight.Bold).fontColor(tc(this.pal, '#3A4E60', 1)).width('100%')
            } else if (line.startsWith('- ') || line.startsWith('* ')) {
              Row({  space: S.spaceMd  }) {
                // v4.23：字符「•」墨迹只有 3.4x3.4vp（AGC 2.1.4.3.2 不达标），
                // 换成系统 circle_fill，fs12 墨迹 11.4x11.4vp。
                SymbolGlyph(sym('bullet'))
                  .fontSize(S.cardTitleSize)
                  .fontColor([tkInk(this.pal, 'brand')])
                Text(line.substring(2)).fontSize(S.midSize).fontColor(tc(this.pal, '#3A4E60', 1)).layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            } else if (line.startsWith('> ')) {
              Text(line.substring(2))
                .fontSize(S.smallSize).fontColor(tc(this.pal, '#78899C', 1))
                .width('100%')
                .padding({  left: S.space2Xl, top: S.spaceXs, bottom: S.spaceXs  })
                .border({ width: { left: 2 }, color: tk(this.pal, 'brandLine') })
                .backgroundColor(tc(this.pal, '#F6FBFE', 0))
            } else {
              Text(line.length > 0 ? line : ' ')
                .fontSize(S.midSize).lineHeight(25).fontColor(tc(this.pal, '#3A4E60', 1)).width('100%')
            }
          }, (line: string, i: number) => `md-${i}-${line.length}`)
        }
        .width('100%')
        .padding({  top: S.spaceLg  })
        .constraintSize({ minHeight: 300 })
        .alignItems(HorizontalAlign.Start)
      }

      // 标签
      Row({  space: S.spaceMd  }) {
        SymbolGlyph(sym('line3')).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#A8B8C6', 1)])
        TextInput({ placeholder: '标签，逗号分隔，比如：选题, 复盘', text: this.editTags })
          .fontSize(S.labelSize)
          .placeholderFont({ size: 11 })
          .placeholderColor(tc(this.pal, '#A8B8C6', 1))
          .fontColor(tk(this.pal, 'text'))
          .caretColor(tk(this.pal, 'brand'))
          .layoutWeight(1)
          .height(32)
          .backgroundColor('#00000000')
          .padding(0)
          .onChange((v: string) => { this.editTags = v; })
      }
      .width('100%')
      .padding({  left: S.spaceXl, right: S.spaceXl  })
      .borderRadius(S.radiusSm)
      .backgroundColor(tc(this.pal, '#F8FBFE', 0))
      .border({ width: 1, color: tk(this.pal, 'line') })
      .alignItems(VerticalAlign.Center)
      .margin({  top: S.spaceLg  })

      // 关联任务
      Column({  space: S.spaceMd  }) {
        Row({  space: S.spaceMd  }) {
          Text('相关任务').fontSize(S.tinySize).fontColor(tc(this.pal, '#8FA2B3', 1))
          Blank()
          // v5.15 可访问性：这两个按钮原来只有 ~18 高 ⇒ 外层套 40 高的透明热区，按钮本身不变
          Row() {
            Text('变成任务')
              .fontSize(S.subSize)
              .fontColor(tkInk(this.pal, 'brandDeep'))
              .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
              .borderRadius(S.radiusSm)
              .backgroundColor(tk(this.pal, 'brandSoft'))
          }
          .height(40)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .onClick(() => { this.toTask(); })
          .accessibilityText('把这条记录变成任务')
          Row() {
            Text('+ 关联一个任务…')
              .fontSize(S.subSize)
              .fontColor(tc(this.pal, '#6A7F92', 1))
              .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceSm, bottom: S.spaceSm  })
              .borderRadius(S.radiusSm)
              .backgroundColor(tc(this.pal, '#F8FBFE', 0))
              .border({ width: 1, color: tk(this.pal, 'line') })
          }
          .height(40)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .bindMenu(this.linkCandidates())
          .accessibilityText('关联一个任务')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.links.length === 0) {
          Text('还没有关联。').fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint'))
        } else {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.links, (l: NoteLink) => {
              Row({  space: S.spaceMd  }) {
                SymbolGlyph(sym('checkCircle')).fontSize(S.cardTitleSize)
                  .fontColor([l.status === 'done' ? tkInk(this.pal, 'study') : tc(this.pal, '#8FA2B3', 1)])
                Text(l.title)
                  .fontSize(S.tinySize).fontColor(tc(this.pal, '#4E6C86', 1)).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 140 })
                // v5.15 可访问性：解除关联的 × 原来只有 14×14 ⇒ 外层套 40×40 的透明热区，× 本身不变
                Row() {
                  SymbolGlyph(sym('close')).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#B9C9D6', 1)])
                }
                .width(40).height(40)
                .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
                .onClick(() => { this.unlink(l.task_id); })
                .accessibilityText(`解除关联 ${l.title}`)
              }
              .padding({  left: S.spaceXl, right: S.spaceSm, top: 0, bottom: 0  })
              .borderRadius(S.radiusSm)
              .backgroundColor(tc(this.pal, '#EFF9F8', 0))
              .border({ width: 1, color: tk(this.pal, 'brandLine') })
              .alignItems(VerticalAlign.Center)
              .margin({  right: S.spaceMd, bottom: S.spaceMd  })
            }, (l: NoteLink) => `lk-${l.task_id}-${this.tick}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({  top: S.spaceXl  })

      Divider().color(tk(this.pal, 'line')).strokeWidth(1).margin({  top: S.spaceSm, bottom: S.spaceSm  })

      // 底部
      Row({  space: S.spaceMd  }) {
        Text('写完点右上角「保存」，保存后自动回到记录列表').fontSize(S.microSize).fontColor(tk(this.pal, 'textHint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({  top: S.spaceMd  })
    }
    .width('100%')
    .padding({  left: S.space4Xl, right: S.space4Xl, top: S.space3Xl, bottom: S.space3Xl  })
    .borderRadius(S.radiusCard)
    .backgroundColor(tk(this.pal, 'card'))
    .border({ width: 1, color: tk(this.pal, 'cardBorder') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder emptyEditor() {
    Column({  space: S.spaceLg  }) {
      SymbolGlyph(sym('squareAndPencil')).fontSize(S.iconXLSize).fontColor([tc(this.pal, '#D5E3EE', 1)])
      Text('选一条记录，或新建一条').fontSize(S.cardTitleSize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#5E7183', 1))
      Text('记录会存在本地数据库，随时可以导出。').fontSize(S.subSize).fontColor(tc(this.pal, '#A8B8C6', 1))
    }
    .width('100%')
    .padding({  top: 44, bottom: 44  })
    .alignItems(HorizontalAlign.Center)
  }


  @Builder pageTop() {
    TopBar({
      primaryText: '新记录',
      onPrimary: () => { this.createNote('', false); },
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Text(`${this.tick}`).fontSize(S.hiddenSize).width(1).height(1).opacity(0)

        Scroll() {
          Column() {
            this.pageTop()

            // page-head（截图上「记录 / 归档」两个 chip 在标题下方左对齐）
            Column({  space: S.spaceMd  }) {
              Text('NOTES · 随手记').fontSize(S.tinySize).fontColor(tc(this.pal, '#9DB0C1', 1)).letterSpacing(1.6)
              Text('先记下来，再慢慢整理。')
                .fontSize(S.sectionSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text')).letterSpacing(-0.2)
              Text(`${this.kLive} 条记录 · 手动保存`)
                .fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({  top: S.space3Xl, bottom: S.spaceXl  })

            Row({  space: S.spaceMd  }) {
              Chip({ text: '记录', active: !this.showArchived, onTap: () => { this.showArchived = false; this.recalc(); } })
              Chip({ text: '归档', active: this.showArchived, onTap: () => { this.showArchived = true; this.recalc(); } })
            }
            .width('100%')
            .padding({  bottom: S.space2Xl  })

            // 新建失败要看得见：以前只赋值不渲染，用户只感觉「点了没反应」
            if (this.newErr.length > 0) {
              FormErr({ msg: this.newErr })
                .margin({  bottom: S.spaceXl  })
            }

            this.listPanel()

            // 手机上编辑器为空的时候也提示
            Column() {
              this.emptyEditor()
            }
            .width('100%')
            .margin({  top: S.spaceXl  })
            .borderRadius(S.radiusCard)
            .backgroundColor(tk(this.pal, 'card'))
            .border({ width: 1, color: tk(this.pal, 'cardBorder') })

            Row().height(R.bottomPad())
          }
          .width('100%')
          .padding({  left: S.pagePad, right: S.pagePad, top: S.pageTop  })
          .alignItems(HorizontalAlign.Start)
        }
          // v5.16：滚动时把右下角悬浮按钮藏起来（它正好压在内容上），停了就回来
          .onDidScroll((x: number, y: number) => { AppStorage.setOrCreate<boolean>('wb_scrolling', true); })
          .onScrollStop(() => { AppStorage.setOrCreate<boolean>('wb_scrolling', false); })
        .onScrollEdge(onEdgeScrolled)
        .onWillScroll(onEdgeWillScroll)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .constraintSize({ maxWidth: 1240 })
      }
      .width('100%')
      .height('100%')

      // v4.4：编辑器改成「居中弹窗」——
      // 以前点「新记录」是整页替换（列表整个被顶掉），显得很突兀；
      // 现在是一张浮在正中的卡片，遮罩压暗背景，点遮罩关闭（有内容会先存）。
      if (this.mEditing && this.activeId >= 0) {
        Stack({ alignContent: Alignment.Center }) {
          // 遮罩
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(23,52,80,0.42)')
            .onClick(() => { this.closeEditor(); })
          // 卡片
          Column() {
            Scroll() {
              Column() {
                this.editorPanel()
              }
              .width('100%')
            }
              // v5.16：滚动时把右下角悬浮按钮藏起来（它正好压在内容上），停了就回来
              .onDidScroll((x: number, y: number) => { AppStorage.setOrCreate<boolean>('wb_scrolling', true); })
              .onScrollStop(() => { AppStorage.setOrCreate<boolean>('wb_scrolling', false); })
            .onScrollEdge(onEdgeScrolled)
            .onWillScroll(onEdgeWillScroll)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .constraintSize({ maxHeight: '82%' })
            .scrollBar(BarState.Off)
            .align(Alignment.TopStart)
          }
          .width('92%')
          .constraintSize({ maxWidth: 520 })
          .borderRadius(S.radiusCard)
          .shadow(sheetShadow(this.pal))
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .zIndex(90)
      }
    }
    .width('100%')
    .height('100%')
    // v5.0：页面底色改成透明，让 Index 根 Stack 上的大光斑透出来
    .backgroundColor(Color.Transparent)
  }
}
