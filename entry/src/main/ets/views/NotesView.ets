// 记录灵感
// 逐块对齐「个人工作台」components/NotesApp.tsx 的手机端：
//   eyebrow「NOTES · 记录灵感」→ h1「先记下来，再慢慢整理。」→「N 条记录 · 手动保存」
//   → 右侧 记录/归档 两个 chip
//   → 左栏：搜索框 + 记录列表（置顶/标题/摘要/来源·时间·标签）
//          + 「随手记一句」虚线卡（4 个种子 + 空白记录）+ 底部统计（本月/标签数/进度条/本周/spark/标签）
//   → 右栏：‹ 全部记录 + 置顶/归档/删除/保存(右上角) + 标题 + 来源·时间·已保存 + 来源胶囊 + 编辑/预览 + 正文 + 关联
// 手机端列表与编辑器是两块屏（mEditing），与工作台的 .notes-grid.m-edit/.m-list 一致。
import { Store } from '../store/Store';
import { C, onFill, S, tc, tk, tkInk } from '../utils/Theme';
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

const SOURCES: string[] = ['灵感', '工作', '学习', '复盘'];
const SEEDS: string[] = ['今天的收获', '一个想法', '待办清单', '复盘素材'];

interface NotePatchBox {
  source?: string;
}

@Component
export struct NotesView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
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
  onNavigate: (page: string) => void = () => {};
  /** v4.4：编辑器浮层开/关时告诉外层（外层要把底部导航藏起来） */
  onOverlay: (open: boolean) => void = () => {};

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    this.unsub();
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
   */
  private closeEditor(silent: boolean = false): void {
    if (!silent) {
      const hasContent: boolean = this.editTitle.trim().length > 0 || this.editBody.trim().length > 0;
      if (hasContent) {
        this.flushSave();
        toast(this.getUIContext(), '已存好');
      }
    }
    this.activeId = -1;
    this.mEditing = false;
    this.onOverlay(false);
    this.links = [];
  }

  /** 手机上手动保存：不再做「停止输入 0.9 秒后自动保存」。 */
  private flushSave(): void {
    const cur: Note | undefined = this.active();
    if (cur === undefined) { return; }
    const changed: boolean = cur.title !== this.editTitle || cur.content !== this.editBody ||
      cur.tags !== this.editTags || cur.source !== this.editSource;
    if (!changed) { return; }
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
    Store.I.updateNote(cur.id, body).then((ok: boolean) => {
      this.saving = false;
      if (ok) {
        const d: Date = new Date();
        const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
        const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
        const ss: string = d.getSeconds() < 10 ? `0${d.getSeconds()}` : `${d.getSeconds()}`;
        this.savedAt = `${hh}:${mm}:${ss}`;
      }
    });
  }

  /** 点「保存」：写回服务器 → 存好了 → 回到记录列表。 */
  private saveNow(): void {
    this.flushSave();
    this.closeEditor(true);
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
    this.flushSave();
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
    .fontColor(tc(this.dark, '#4E6C86', 1))
    .radius(12)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
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
    Column({ space: 3 }) {
      Row({ space: 4 }) {
        if (n.pinned === 1) {
          SymbolGlyph(sym('pin')).fontSize(14).fontColor([tkInk(this.dark, 'brand')])
        }
        Text(n.title.length > 0 ? n.title : '(无标题)')
          .fontSize(11.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(tc(this.dark, '#2C4257', 1))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (n.content.length > 0 && n.content !== n.title) {
        Text(this.snippet(n))
          .fontSize(10)
          .fontColor(tc(this.dark, '#8FA2B3', 1))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Text(`${n.source} · ${n.updated_at.substring(5, 10).replace('-', '/')} ${D.hm(n.updated_at)}${n.tags.length > 0 ? ` · ${n.tags}` : ''}`)
        .fontSize(8.5)
        .fontColor(tc(this.dark, '#A8B8C6', 1))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .borderRadius(11)
    .backgroundColor(this.activeId === n.id ? tk(this.dark, 'brandSoft') : '#00000000')
    .border({
      width: 1,
      color: this.activeId === n.id ? tk(this.dark, 'brandLine') : '#00000000'
    })
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 2 })
    .onClick(() => { this.open(n.id); })
  }

  /** 「随手记一句」虚线卡 */
  @Builder hintCard() {
    Column({ space: 5 }) {
      SymbolGlyph(sym('pen')).fontSize(14).fontColor([tc(this.dark, '#9FE0DC', 1)])
      Text('随手记一句').fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5E7183', 1))
      Text('想到什么先扔进来，以后再整理。')
        .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).textAlign(TextAlign.Center)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(SEEDS, (s: string) => {
          Text(s)
            .fontSize(9.5)
            .fontColor(tc(this.dark, '#7C93A6', 1))
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .borderRadius(9)
            .backgroundColor(tc(this.dark, '#FFFFFF', 0))
            .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E6F1F9', 2), 2) })
            .margin({ right: 6, bottom: 6 })
            .onClick(() => { this.createNote(s, false); })
        }, (s: string) => `seed-${s}`)
      }
      .width('100%')
      .margin({ top: 4 })

      Text('+ 空白记录')
        .fontSize(10)
        .fontColor(tc(this.dark, '#6A7F92', 1))
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .borderRadius(9)
        .backgroundColor(tc(this.dark, '#FFFFFF', 0))
        .border({ width: 1, color: tk(this.dark, 'line') })
        .margin({ top: 2 })
        .onClick(() => { this.createNote('', false); })
    }
    .width('100%')
    .padding({ top: 14, bottom: 12, left: 10, right: 10 })
    .borderRadius(16)
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#DDEBF4', 2), 2), style: BorderStyle.Dashed })
    .linearGradient({ angle: 180, colors: [[this.dark ? '#18222E' : '#FBFDFF', 0], [this.dark ? '#141D27' : '#F6FBFE', 1]] })
    .alignItems(HorizontalAlign.Center)
  }

  /** 底部统计：本月记录 / 标签数 / 进度条 / 本周 / spark / 标签 */
  @Builder sideFoot() {
    Column({ space: 7 }) {
      Divider().color(tk(this.dark, 'line')).strokeWidth(1)

      Row({ space: 8 }) {
        Text('本月记录').fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1))
        Text(`${this.kMonth}`).fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#2B4055', 1))
        Blank()
        Text(`${this.kTags} 个标签`).fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 进度条
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(5).borderRadius(99).backgroundColor(tc(this.dark, '#EEF5FA', 0))
        Row()
          .width(`${Math.min(100, this.kMonth * 8)}%`)
          .height(5)
          .borderRadius(99)
          .linearGradient({ angle: 90, colors: [['#1C7C74', 0], ['#12706B', 1]] })
      }
      .width('100%')
      .height(5)

      Row({ space: 8 }) {
        Text('本周').fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1))
        Text(`${this.kWeek}`).fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#2B4055', 1))
        Blank()
        Text('每天记一笔').fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // spark（最近 7 天）
      Row({ space: 3 }) {
        ForEach(this.weekSeries(), (v: number, i: number) => {
          Column() {
            Blank()
            Row()
              .width('100%')
              .height(`${Math.max(8, v / this.weekMax() * 100)}%`)
              .borderRadius({ topLeft: 3, topRight: 3, bottomLeft: 2, bottomRight: 2 })
              .backgroundColor(i === 6 ? tc(this.dark, '#3AC8C2', 0) : (v > 0 ? tc(this.dark, '#7FE3D6', 0) : tc(this.dark, '#DFF3F8', 0)))
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
        Text(D.slashMd(D.dateAdd(new Date(), -6))).fontSize(8.5).fontColor(tc(this.dark, '#A8B8C6', 1))
        Blank()
        Text('今天').fontSize(8.5).fontColor(tc(this.dark, '#A8B8C6', 1))
      }
      .width('100%')

      if (this.kTags > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.allTags().slice(0, 6), (t: string) => {
            Text(`#${t}`)
              .fontSize(9.5)
              .fontColor(this.tagFilter === t ? onFill(this.dark) : tc(this.dark, '#4E6C86', 1))
              .backgroundColor(this.tagFilter === t ? tk(this.dark, 'brandDeep') : tc(this.dark, '#F2F8FD', 0))
              .border({ width: 1, color: this.tagFilter === t ? tk(this.dark, 'brandDeep') : tc(this.dark, '#E4F1FA', 2) })
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .margin({ right: 5, bottom: 5 })
              .onClick(() => { this.tagFilter = this.tagFilter === t ? '' : t; this.recalc(); })
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
      Row({ space: 7 }) {
        SymbolGlyph(sym('search')).fontSize(13).fontColor([tc(this.dark, '#A8B8C6', 1)])
        TextInput({ placeholder: '搜索记录、标签…', text: this.q })
          .fontSize(11.5)
          .placeholderFont({ size: 11.5 })
          .placeholderColor(tc(this.dark, '#A8B8C6', 1))
          .fontColor(tk(this.dark, 'text'))
          .caretColor(tk(this.dark, 'brand'))
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#00000000')
          .padding(0)
          .onChange((v: string) => { this.q = v; })
      }
      .width('100%')
      .padding({ left: 10, right: 8 })
      .borderRadius(10)
      .backgroundColor(tc(this.dark, '#F8FBFE', 0))
      .border({ width: 1, color: tk(this.dark, 'line') })
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 8 })

      // 记录列表
      Column() {
        if (this.kList === 0) {
          Column({ space: 4 }) {
            Text(this.showArchived ? '归档里还是空的' : '还没有记录')
              .fontSize(12).fontColor(tc(this.dark, '#5E7183', 1))
            Text(this.showArchived ? '暂时用不上的记录可以归档。' : '想到什么，先扔进来。')
              .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1))
          }
          .width('100%')
          .padding({ top: 30, bottom: 30 })
          .alignItems(HorizontalAlign.Center)
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
      .margin({ top: 10, bottom: 10 })

      // 底部统计
      this.sideFoot()

      // 撤销条
      if (this.undoId >= 0) {
        Row({ space: 8 }) {
          Row().width(6).height(6).borderRadius(3).backgroundColor(tk(this.dark, 'brand'))
          Text(`已删除「${this.undoTitle.length > 0 ? this.undoTitle : '无标题'}」`)
            .fontSize(10)
            .fontColor(tc(this.dark, '#1F6E77', 1))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('撤销')
            .fontSize(10)
            .fontColor(tkInk(this.dark, 'brandDeep'))
            .fontWeight(FontWeight.Medium)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(7)
            .backgroundColor(tc(this.dark, '#FFFFFF', 0))
            .onClick(() => { this.undoDelete(); })
        }
        .width('100%')
        .padding({ left: 10, right: 8, top: 8, bottom: 8 })
        .borderRadius(11)
        .backgroundColor(tc(this.dark, '#F2FBF9', 0))
        .border({ width: 1, color: tk(this.dark, 'brandLine') })
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .borderRadius(S.radiusCard)
    .backgroundColor(tk(this.dark, 'card'))
    .border({ width: 1, color: tk(this.dark, 'cardBorder') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder editorPanel() {
    Column() {
      // 顶部：返回 + 置顶 / 归档 / 删除 + 保存（保存按钮在右上角，v2.9）
      Row({ space: 6 }) {
        Row({ space: 3 }) {
          SymbolGlyph(sym('close')).fontSize(14).fontColor([tkInk(this.dark, 'brandDeep')])
          Text('关闭').fontSize(11.5).fontColor(tkInk(this.dark, 'brandDeep'))
        }
        .onClick(() => { this.closeEditor(); })
        Blank()
        SymbolGlyph(sym('pin')).fontSize(16)
          .fontColor([this.active()?.pinned === 1 ? tkInk(this.dark, 'brand') : tc(this.dark, '#C9DAE6', 1)])
          .padding(5)
          .onClick(() => { this.togglePin(); })
        SymbolGlyph(sym('archive')).fontSize(16).fontColor([tc(this.dark, '#C9DAE6', 1)])
          .padding(5)
          .onClick(() => { this.toggleArchive(); })
        SymbolGlyph(sym('trash')).fontSize(16).fontColor([tc(this.dark, '#E0B4A4', 1)])
          .padding(5)
          .onClick(() => { this.remove(); })
        Text(this.saving ? '保存中…' : '保存')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(onFill(this.dark))
          .padding({ left: 13, right: 13, top: 5, bottom: 5 })
          .borderRadius(9)
          .backgroundColor(this.saving ? tc(this.dark, '#A9BECF', 0) : tk(this.dark, 'brand'))
          .margin({ left: 4 })
          .onClick(() => { this.saveNow(); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // v4.2：主内容（原来叫「标题」，现在就是正文的第一块，字最大）
      TextInput({ placeholder: '写点什么…', text: this.editTitle })
        .fontSize(23)
        .placeholderFont({ size: 23 })
        .placeholderColor(tc(this.dark, '#A8B8C6', 1))
        .fontWeight(FontWeight.Bold)
        .fontColor(tk(this.dark, 'text'))
        .backgroundColor('#00000000')
        .padding({ left: 0, right: 0 })
        .margin({ top: 4 })
        .onChange((v: string) => { this.editTitle = v; })
      Text('上面这句就是这条记录的内容。下面想补充再写，不写也行。')
        .fontSize(9.5)
        .fontColor(tc(this.dark, '#A8B8C6', 1))
        .width('100%')
        .margin({ top: 2, bottom: 2 })

      // 来源 · 时间 · 已保存
      Row({ space: 8 }) {
        Text(this.editSource).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
        Text(this.active() !== undefined
          ? `${D.key(D.parse(D.dateOf(this.active()!.created_at))).replace(/-/g, '/')} ${D.hm(this.active()!.created_at)}`
          : '').fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
        if (this.savedAt.length > 0) {
          Text(this.saving ? '保存中…' : `已保存 ${this.savedAt}`).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
        }
      }
      .width('100%')
      .margin({ top: 3, bottom: 8 })

      // 来源胶囊 + 编辑/预览
      Row({ space: 5 }) {
        ForEach(SOURCES, (s: string) => {
          Text(s)
            .fontSize(9.5)
            .fontColor(this.editSource === s ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#7E93A6', 1))
            .backgroundColor(this.editSource === s ? tk(this.dark, 'brandSoft') : tc(this.dark, '#F8FBFE', 0))
            .border({ width: 1, color: this.editSource === s ? tk(this.dark, 'brandLine') : tk(this.dark, 'line') })
            .borderRadius(999)
            .padding({ left: 9, right: 9, top: 3, bottom: 3 })
            .onClick(() => { this.setSource(s); })
        }, (s: string) => `src-${s}`)
        Blank()
        Row({ space: 3 }) {
          SymbolGlyph(sym('pen')).fontSize(14)
            .fontColor([this.preview ? tc(this.dark, '#A8B8C6', 1) : tkInk(this.dark, 'brandDeep')])
          Text('编辑').fontSize(9.5)
            .fontColor(this.preview ? tc(this.dark, '#A8B8C6', 1) : tkInk(this.dark, 'brandDeep'))
        }
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .borderRadius(7)
        .onClick(() => { this.preview = false; })
        Row({ space: 3 }) {
          SymbolGlyph(sym('eye')).fontSize(14)
            .fontColor([this.preview ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#A8B8C6', 1)])
          Text('预览').fontSize(9.5)
            .fontColor(this.preview ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#A8B8C6', 1))
        }
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .borderRadius(7)
        .onClick(() => { this.preview = true; })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 8 })

      Divider().color('#EDF4FA').strokeWidth(1)

      // 正文 / 预览（v4.2：正文降为「补充」，字号更小、位置更次要）
      if (!this.preview) {
        Text('补充（可选）').fontSize(10).fontColor(tc(this.dark, '#8FA2B3', 1)).width('100%').margin({ top: 6 })
        TextArea({ placeholder: '再补几句…', text: this.editBody })
          .fontSize(12.5)
          .placeholderFont({ size: 12.5 })
          .placeholderColor(tc(this.dark, '#A8B8C6', 1))
          .fontColor(tk(this.dark, 'text'))
          .caretColor(tk(this.dark, 'brand'))
          .lineHeight(21)
          .constraintSize({ minHeight: 110 })
          .backgroundColor('#00000000')
          .padding({ left: 0, right: 0, top: 6 })
          .onChange((v: string) => { this.editBody = v; })
      } else {
        Column({ space: 5 }) {
          if (this.editBody.trim().length === 0) {
            Text('（还没有内容）').fontSize(12).fontColor(tc(this.dark, '#C6D4E0', 1))
          }
          ForEach(this.mdLines(), (line: string, i: number) => {
            if (line.startsWith('### ')) {
              Text(line.substring(4)).fontSize(13).fontWeight(FontWeight.Bold).fontColor(tc(this.dark, '#3A4E60', 1)).width('100%')
            } else if (line.startsWith('## ')) {
              Text(line.substring(3)).fontSize(15).fontWeight(FontWeight.Bold).fontColor(tc(this.dark, '#3A4E60', 1)).width('100%')
            } else if (line.startsWith('# ')) {
              Text(line.substring(2)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(tc(this.dark, '#3A4E60', 1)).width('100%')
            } else if (line.startsWith('- ') || line.startsWith('* ')) {
              Row({ space: 6 }) {
                // v4.23：字符「•」墨迹只有 3.4x3.4vp（AGC 2.1.4.3.2 不达标），
                // 换成系统 circle_fill，fs12 墨迹 11.4x11.4vp。
                SymbolGlyph(sym('bullet'))
                  .fontSize(14)
                  .fontColor([tkInk(this.dark, 'brand')])
                Text(line.substring(2)).fontSize(13).fontColor(tc(this.dark, '#3A4E60', 1)).layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            } else if (line.startsWith('> ')) {
              Text(line.substring(2))
                .fontSize(12).fontColor(tc(this.dark, '#78899C', 1))
                .width('100%')
                .padding({ left: 12, top: 2, bottom: 2 })
                .border({ width: { left: 2 }, color: tk(this.dark, 'brandLine') })
                .backgroundColor(tc(this.dark, '#F6FBFE', 0))
            } else {
              Text(line.length > 0 ? line : ' ')
                .fontSize(13).lineHeight(25).fontColor(tc(this.dark, '#3A4E60', 1)).width('100%')
            }
          }, (line: string, i: number) => `md-${i}-${line.length}`)
        }
        .width('100%')
        .padding({ top: 8 })
        .constraintSize({ minHeight: 300 })
        .alignItems(HorizontalAlign.Start)
      }

      // 标签
      Row({ space: 6 }) {
        SymbolGlyph(sym('line3')).fontSize(14).fontColor([tc(this.dark, '#A8B8C6', 1)])
        TextInput({ placeholder: '标签，逗号分隔，比如：选题, 复盘', text: this.editTags })
          .fontSize(11)
          .placeholderFont({ size: 11 })
          .placeholderColor(tc(this.dark, '#A8B8C6', 1))
          .fontColor(tk(this.dark, 'text'))
          .caretColor(tk(this.dark, 'brand'))
          .layoutWeight(1)
          .height(32)
          .backgroundColor('#00000000')
          .padding(0)
          .onChange((v: string) => { this.editTags = v; })
      }
      .width('100%')
      .padding({ left: 10, right: 10 })
      .borderRadius(9)
      .backgroundColor(tc(this.dark, '#F8FBFE', 0))
      .border({ width: 1, color: tk(this.dark, 'line') })
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })

      // 关联任务
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text('相关任务').fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1))
          Blank()
          Text('变成任务')
            .fontSize(10)
            .fontColor(tkInk(this.dark, 'brandDeep'))
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(8)
            .backgroundColor(tk(this.dark, 'brandSoft'))
            .onClick(() => { this.toTask(); })
          Text('+ 关联一个任务…')
            .fontSize(10)
            .fontColor(tc(this.dark, '#6A7F92', 1))
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(8)
            .backgroundColor(tc(this.dark, '#F8FBFE', 0))
            .border({ width: 1, color: tk(this.dark, 'line') })
            .bindMenu(this.linkCandidates())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.links.length === 0) {
          Text('还没有关联。').fontSize(9).fontColor(tk(this.dark, 'textHint'))
        } else {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.links, (l: NoteLink) => {
              Row({ space: 5 }) {
                SymbolGlyph(sym('checkCircle')).fontSize(14)
                  .fontColor([l.status === 'done' ? tkInk(this.dark, 'study') : tc(this.dark, '#8FA2B3', 1)])
                Text(l.title)
                  .fontSize(9.5).fontColor(tc(this.dark, '#4E6C86', 1)).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 140 })
                SymbolGlyph(sym('close')).fontSize(14).fontColor([tc(this.dark, '#B9C9D6', 1)])
                  .onClick(() => { this.unlink(l.task_id); })
              }
              .padding({ left: 9, right: 7, top: 5, bottom: 5 })
              .borderRadius(8)
              .backgroundColor(tc(this.dark, '#EFF9F8', 0))
              .border({ width: 1, color: tk(this.dark, 'brandLine') })
              .alignItems(VerticalAlign.Center)
              .margin({ right: 5, bottom: 5 })
            }, (l: NoteLink) => `lk-${l.task_id}-${this.tick}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 10 })

      Divider().color(tk(this.dark, 'line')).strokeWidth(1).margin({ top: 4, bottom: 3 })

      // 底部
      Row({ space: 6 }) {
        Text('写完点右上角「保存」，保存后自动回到记录列表').fontSize(8.5).fontColor(tk(this.dark, 'textHint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(S.radiusCard)
    .backgroundColor(tk(this.dark, 'card'))
    .border({ width: 1, color: tk(this.dark, 'cardBorder') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder emptyEditor() {
    Column({ space: 7 }) {
      SymbolGlyph(sym('squareAndPencil')).fontSize(30).fontColor([tc(this.dark, '#D5E3EE', 1)])
      Text('选一条记录，或新建一条').fontSize(14).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5E7183', 1))
      Text('记录会存在本地数据库，随时可以导出。').fontSize(10.5).fontColor(tc(this.dark, '#A8B8C6', 1))
    }
    .width('100%')
    .padding({ top: 44, bottom: 44 })
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
        Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

        Scroll() {
          Column() {
            this.pageTop()

            // page-head（截图上「记录 / 归档」两个 chip 在标题下方左对齐）
            Column({ space: 5 }) {
              Text('NOTES · 记录灵感').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
              Text('先记下来，再慢慢整理。')
                .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
              Text(`${this.kLive} 条记录 · 手动保存`)
                .fontSize(11).fontColor(tk(this.dark, 'textSub'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 14, bottom: 10 })

            Row({ space: 6 }) {
              Chip({ text: '记录', active: !this.showArchived, onTap: () => { this.showArchived = false; this.recalc(); } })
              Chip({ text: '归档', active: this.showArchived, onTap: () => { this.showArchived = true; this.recalc(); } })
            }
            .width('100%')
            .padding({ bottom: 12 })

            // 新建失败要看得见：以前只赋值不渲染，用户只感觉「点了没反应」
            if (this.newErr.length > 0) {
              FormErr({ msg: this.newErr })
                .margin({ bottom: 10 })
            }

            this.listPanel()

            // 手机上编辑器为空的时候也提示
            Column() {
              this.emptyEditor()
            }
            .width('100%')
            .margin({ top: 10 })
            .borderRadius(S.radiusCard)
            .backgroundColor(tk(this.dark, 'card'))
            .border({ width: 1, color: tk(this.dark, 'cardBorder') })

            Row().height(S.pageBottom)
          }
          .width('100%')
          .padding({ left: S.pagePad, right: S.pagePad, top: S.pageTop })
          .alignItems(HorizontalAlign.Start)
        }
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
          .shadow({ radius: 30, color: 'rgba(23,52,80,0.26)', offsetX: 0, offsetY: 14 })
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .zIndex(90)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(tk(this.dark, 'bg'))
  }
}
