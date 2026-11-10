/**
 * TaskSheet —— 任务添加/编辑抽屉，逐项对齐个人工作台 components/TaskModal.tsx。
 *
 * v4.12（用户拍板）：时间只留两个框 ——
 *   任务 → 备注 → [分类 | 优先级] → [项目 | 标签] → 状态三段 → [截止时间 | 预计分钟]
 *   → 开始时间 → 重复 → 说明行 → 编辑态「相关记录」 → 错误条 → 取消/保存
 *   截止时间留空 = 长期任务；开始时间留空 = 自动按「创建时间 vs 截止时间」取更早的；
 *   结束时间不再手填 = 开始时间 + 预计时长（有截止时间就取更早的）。
 *
 * v4.20：零权限 —— 「提醒」选项整块删掉（本 App 不发系统通知、不申请任何权限）。
 *   remind_min 字段在 db 里保留：老任务的提前量继续生效（App 内铃铛清单照旧提前显示），
 *   编辑老任务时不带 remind_min 字段 ⇒ 不会把老数据抹掉。
 */
import { C, areaLabel, tk, tc } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { sym } from './Icon';
import {
  SheetHead, FormBox, SegTabs, PickerBox, DateBox, FormErr, HintLine, SheetActs
} from './FormKit';
import {
  Task, TaskCreate, TaskUpdate, Project, Area, Priority, TaskStatus, RepeatRule,
  TaskNoteLink, TaskNoteLinksResp, OkResp, EventItem
} from '../api/Types';
import { Store } from '../store/Store';
import { Repo } from '../db/Repo';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from './ConfirmDialog';
import { R } from '../utils/Responsive';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

interface LinkBody { note_id: number; task_id: number }

const AREAS: string[] = ['work', 'side', 'media', 'study', 'life'];
const PRIORITIES: string[] = ['high', 'med', 'low'];
const PRIORITY_LABELS: string[] = ['高', '中', '低'];
const STATUSES: string[] = ['todo', 'doing', 'done'];
const RULE_KEYS: string[] = ['none', 'daily', 'weekdays', 'weekly', 'monthly'];
const RULE_LABELS: string[] = ['不重复', '每天', '每个工作日', '每周', '每月'];

@Component
export struct TaskSheet {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop @Watch('reload') editingId: number = -1;
  @Prop @Watch('reload') defaultStatus: string = 'todo';
  onSaved: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  @State title: string = '';
  @State note: string = '';
  @State area: string = 'work';
  @State priority: string = 'med';
  @State status: string = 'todo';
  @State projectId: number = -1;
  @State tags: string = '';
  @State dueDate: string = '';
  @State estMin: string = '';
  @State startAt: string = '';
  @State rule: string = 'none';
  @State busy: boolean = false;
  @State err: string = '';
  @State linked: TaskNoteLink[] = [];
  /** v4.12：关联日程（-1 = 不关联） */
  @State linkEventId: number = -1;
  @State linkEventLabels: string[] = [];
  @State linkEventIds: number[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  /** bindSheet 会复用同一组件实例；切换任务或再次新建时 @Watch 触发整表重置 */
  reload(): void {
    this.title = '';
    this.note = '';
    this.area = 'work';
    this.priority = 'med';
    this.status = this.defaultStatus;
    this.projectId = -1;
    this.tags = '';
    this.dueDate = '';
    this.estMin = '';
    this.startAt = '';
    this.rule = 'none';
    this.busy = false;
    this.err = '';
    this.linked = [];
    this.linkEventId = -1;
    this.buildEventChoices();
    if (this.editingId > 0) {
      const t: Task | undefined = Store.I.findTask(this.editingId);
      if (t !== undefined) {
        this.title = t.title;
        this.note = t.note !== null ? t.note : '';
        this.area = t.area;
        this.priority = t.priority;
        this.status = t.status;
        this.projectId = t.project_id !== null ? t.project_id : -1;
        this.tags = t.tags !== null ? t.tags : '';
        this.dueDate = t.due_date !== null ? t.due_date : '';
        this.estMin = t.estimate_min !== null ? `${t.estimate_min}` : '';
        this.startAt = t.scheduled_start !== null ? t.scheduled_start : '';
        this.rule = t.repeat_rule;
      }
      this.loadLinks();
      this.loadTaskEventLink();
    }
  }

  /** v4.12：可选的日程（最近的 20 条） */
  private buildEventChoices(): void {
    const labels: string[] = ['不关联日程'];
    const ids: number[] = [-1];
    const list: EventItem[] = [...Store.I.events].sort((a: EventItem, b: EventItem) => {
      return a.start_at < b.start_at ? -1 : (a.start_at > b.start_at ? 1 : 0);
    });
    let n: number = 0;
    for (const e of list) {
      if (n >= 20) { break; }
      labels.push(`${D.slashMd(D.parse(e.start_at))} ${D.hm(e.start_at)} · ${e.title}`);
      ids.push(e.id);
      n += 1;
    }
    this.linkEventLabels = labels;
    this.linkEventIds = ids;
  }

  /** 编辑态：回显已关联的日程 */
  private async loadTaskEventLink(): Promise<void> {
    try {
      const ids: number[] = await Repo.eventIdsOfTask(this.editingId);
      if (ids.length > 0) { this.linkEventId = ids[0]; }
    } catch (e) {
      this.linkEventId = -1;
    }
  }

  private linkEventText(): string {
    for (let i = 0; i < this.linkEventIds.length; i++) {
      if (this.linkEventIds[i] === this.linkEventId) { return this.linkEventLabels[i]; }
    }
    return '不关联日程';
  }

  private async loadLinks(): Promise<void> {
    try {
      const r: TaskNoteLinksResp = await Repo.taskLinks(this.editingId);
      this.linked = r && r.links ? r.links : [];
    } catch (e) {
      this.linked = [];
    }
  }

  private async addLink(noteId: number): Promise<void> {
    const body: LinkBody = { note_id: noteId, task_id: this.editingId };
    try {
      await Repo.addLink(body.note_id, body.task_id);
      await this.loadLinks();
    } catch (e) {
      this.err = '关联失败，再试一次';
    }
  }

  private async removeLink(noteId: number): Promise<void> {
    const body: LinkBody = { note_id: noteId, task_id: this.editingId };
    try {
      await Repo.removeLink(body.note_id, body.task_id);
      this.linked = this.linked.filter((l: TaskNoteLink) => l.note_id !== noteId);
    } catch (e) {
      this.err = '取消关联失败';
    }
  }

  private linkNoteIds(): number[] {
    const out: number[] = [];
    for (const n of Store.I.notes) {
      let used: boolean = false;
      for (const l of this.linked) {
        if (l.note_id === n.id) {
          used = true;
          break;
        }
      }
      if (!used) {
        out.push(n.id);
      }
    }
    return out;
  }

  private linkOptions(): string[] {
    const out: string[] = [];
    for (const n of Store.I.notes) {
      let used: boolean = false;
      for (const l of this.linked) {
        if (l.note_id === n.id) {
          used = true;
          break;
        }
      }
      if (!used) {
        out.push(n.title.length > 0 ? n.title : '无标题记录');
      }
    }
    return out;
  }

  // ── 字面量联合类型收窄 ──
  private areaVal(): Area {
    if (this.area === 'side') { return 'side'; }
    if (this.area === 'media') { return 'media'; }
    if (this.area === 'study') { return 'study'; }
    if (this.area === 'life') { return 'life'; }
    return 'work';
  }

  private priorityVal(): Priority {
    if (this.priority === 'high') { return 'high'; }
    if (this.priority === 'low') { return 'low'; }
    return 'med';
  }

  private statusVal(): TaskStatus {
    if (this.status === 'doing') { return 'doing'; }
    if (this.status === 'done') { return 'done'; }
    return 'todo';
  }

  private ruleVal(): RepeatRule {
    if (this.rule === 'daily') { return 'daily'; }
    if (this.rule === 'weekdays') { return 'weekdays'; }
    if (this.rule === 'weekly') { return 'weekly'; }
    if (this.rule === 'monthly') { return 'monthly'; }
    return 'none';
  }

  private projNames(): string[] {
    const out: string[] = ['不归项目'];
    for (const p of Store.I.projects) {
      out.push(p.name);
    }
    return out;
  }

  private projText(): string {
    if (this.projectId < 0) {
      return '不归项目';
    }
    for (const p of Store.I.projects as Project[]) {
      if (p.id === this.projectId) {
        return p.name;
      }
    }
    return '不归项目';
  }

  /** 工作台同时发 project（文本）与 project_id */
  private projBody(): string {
    const t: string = this.projText();
    return t === '不归项目' ? '' : t;
  }

  private priorityText(): string {
    for (let i = 0; i < PRIORITIES.length; i++) {
      if (PRIORITIES[i] === this.priority) { return PRIORITY_LABELS[i]; }
    }
    return '中';
  }

  private ruleIndex(): number {
    for (let i = 0; i < RULE_KEYS.length; i++) {
      if (RULE_KEYS[i] === this.rule) { return i; }
    }
    return 0;
  }

  private dueText(): string {
    return this.dueDate.length > 0 ? this.dueDate.slice(0, 10) : '不设 · 长期任务';
  }

  private startText(): string {
    return this.startAt.length >= 16 ? this.startAt.replace('T', ' ').slice(0, 16) : '选择日期时间';
  }


  private pickDate(current: string, onPick: (v: string) => void): void {
    let sel: Date = new Date();
    if (current.length >= 10) { sel = D.parse(current); }
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2035, 11, 31),
      selected: sel,
      onDateAccept: (d: Date) => { onPick(D.key(d)); }
    });
  }

  /** 开始时间缺省值：创建时间和截止时间取更早的那个
   *  （截止时间已经过去 ⇒ 开始时间就落在截止那天） */
  private defaultStart(due: string): string {
    const created: string = D.now();
    if (created > `${due}T23:59`) {
      return `${due}T00:00`;
    }
    return created;
  }

  /** 结束时间 = 开始时间 + 预计时长（没填时长按 30 分钟）；有截止时间就取更早的 */
  private endOf(start: string, est: number | null, due: string | null): string {
    const dur: number = est !== null && est > 0 ? est : 30;
    const s: Date = D.parse(start);
    s.setMinutes(s.getMinutes() + dur);
    let end: Date = s;
    if (due !== null) {
      const dueEnd: Date = D.parse(`${due}T23:59`);
      if (dueEnd.getTime() < end.getTime()) { end = dueEnd; }
    }
    const y: number = end.getFullYear();
    const mo: string = D.p(end.getMonth() + 1);
    const da: string = D.p(end.getDate());
    const hh: string = D.p(end.getHours());
    const mi: string = D.p(end.getMinutes());
    return `${y}-${mo}-${da}T${hh}:${mi}`;
  }

  private pickDateTime(current: string, onPick: (v: string) => void): void {
    let sel: Date = new Date();
    let hh: number = 9;
    let mm: number = 0;
    if (current.length >= 16) {
      sel = D.parse(current);
      hh = sel.getHours();
      mm = sel.getMinutes();
    }
    const ui = this.getUIContext();
    ui.showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2035, 11, 31),
      selected: sel,
      onDateAccept: (d: Date) => {
        const base: Date = new Date(d.getFullYear(), d.getMonth(), d.getDate(), hh, mm, 0, 0);
        ui.showTimePickerDialog({
          selected: base,
          useMilitaryTime: true,
          onAccept: (r: TimePickerResult) => {
            const h: string = r.hour < 10 ? `0${r.hour}` : `${r.hour}`;
            const m: string = r.minute < 10 ? `0${r.minute}` : `${r.minute}`;
            onPick(`${D.key(d)}T${h}:${m}`);
          }
        });
      }
    });
  }

  private async save(): Promise<void> {
    const title: string = this.title.trim();
    if (title.length === 0) { this.err = '先写个任务名'; return; }
    this.busy = true;
    this.err = '';

    const due: string | null = this.dueDate.length > 0 ? this.dueDate : null;
    let est: number | null = null;
    if (this.estMin.trim().length > 0) {
      const n: number = parseInt(this.estMin.trim(), 10);
      if (!isNaN(n) && n > 0) { est = n; }
    }
    // v4.12：开始时间 —— 填了就用；没填但有截止时间，就按「创建时间 vs 截止时间」取更早的；
    //        连截止时间都没填（长期任务）就不设开始时间 ⇒ 它不进日历、不进本周安排。
    let st: string | null = this.startAt.length > 0 ? this.startAt : null;
    if (st === null && due !== null) {
      st = this.defaultStart(due);
    }
    // v4.12：结束时间不再手填 —— 开始时间 + 预计时长（有截止时间就取更早的）
    let en: string | null = null;
    if (st !== null) {
      en = this.endOf(st, est, due);
    }
    const pid: number | null = this.projectId > 0 ? this.projectId : null;
    const proj: string = this.projBody();

    let ok: boolean = false;
    if (this.editingId > 0) {
      const body: TaskUpdate = {
        title: title,
        note: this.note,
        area: this.areaVal(),
        priority: this.priorityVal(),
        status: this.statusVal(),
        due_date: due,
        scheduled_start: st,
        scheduled_end: en,
        estimate_min: est,
        project: proj,
        project_id: pid,
        tags: this.tags,
        repeat_rule: this.ruleVal()
      };
      ok = await Store.I.updateTask(this.editingId, body);
    } else {
      const body: TaskCreate = {
        title: title,
        note: this.note,
        area: this.areaVal(),
        priority: this.priorityVal(),
        status: this.statusVal(),
        due_date: due,
        scheduled_start: st,
        scheduled_end: en,
        estimate_min: est,
        project: proj,
        project_id: pid,
        tags: this.tags,
        repeat_rule: this.ruleVal()
      };
      ok = await Store.I.addTask(body);
    }

    this.busy = false;
    if (ok) {
      // v4.12：把选好的日程关联上
      const tid: number = this.editingId > 0 ? this.editingId : Store.I.lastTaskId;
      if (this.linkEventId > 0 && tid > 0) {
        await Store.I.linkTaskEvent(tid, this.linkEventId);
      }
      this.onSaved();
    } else {
      this.err = Store.I.lastError.length > 0 ? Store.I.lastError : '保存失败，再试一次';
    }
  }

  private remove(): void {
    const nm: string = this.title.length > 0 ? this.title : '这条任务';
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '删除这条任务？', `「${nm}」会被移除，删除后无法恢复。`, '删除',
      () => { this.doRemove(); });
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

  private async doRemove(): Promise<void> {
    this.busy = true;
    const ok: boolean = await Store.I.deleteTask(this.editingId);
    this.busy = false;
    if (ok) {
      this.onCancel();
    } else {
      this.err = Store.I.lastError.length > 0 ? Store.I.lastError : '删除失败，再试一次';
    }
  }

  /** 编辑态「相关记录」区（.note-links） */
  @Builder noteLinks() {
    Column({ space: 7 }) {
      Text('相关记录').fontSize(10.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#8FA2B3', 1))
      if (this.linked.length === 0) {
        Text('还没有记录提到它。').fontSize(11).fontColor(tc(this.dark, '#A9BCCA', 1))
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.linked, (l: TaskNoteLink) => {
          Row({ space: 5 }) {
            Text(l.title.length > 0 ? l.title : '无标题记录')
              .fontSize(10.5).fontColor(tc(this.dark, '#1B7F76', 1)).maxLines(1)
            SymbolGlyph(sym('close')).fontSize(14).fontColor([tc(this.dark, '#1B7F76', 1)])
              .onClick(() => { this.removeLink(l.note_id); })
          }
          .padding({ left: 9, right: 5, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor(tc(this.dark, '#EAF8F6', 0))
          .border({ width: 1, color: tc(this.dark, tc(this.dark, '#C9EDE8', 2), 2) })
          .margin({ right: 6, bottom: 6 })
        }, (l: TaskNoteLink) => `nl-${l.id}`)
      }
      .width('100%')

      if (this.linkOptions().length > 0) {
        PickerBox({
          text: '+ 关联一条记录…',
          options: this.linkOptions(),
          onPick: (i: number) => { this.addLink(this.linkNoteIds()[i]); }
        })
      }
    }
    .width('100%')
    .padding({ left: 11, right: 11, top: 9, bottom: 9 })
    .borderRadius(11)
    .backgroundColor(tc(this.dark, '#FAFCFE', 0))
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E9F2F9', 2), 2) })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Column() {
        SheetHead({
          title: this.editingId > 0 ? '编辑任务' : '添加任务',
          sub: this.editingId > 0 ? '改完直接保存，不用刷新。' : '先记下来，细节以后再补也可以。',
          showClose: true,
          onClose: () => { this.onCancel(); }
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18 })

      Scroll() {
        Column({ space: 11 }) {
          FormBox({ label: '任务' }) {
            TextInput({ placeholder: '比如：把周报写完发出去', text: this.title })
              .onChange((v: string) => { this.title = v; })
              .fontSize(12).height(36)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
              .border({ width: 1, color: tk(this.dark, 'line') })
              .padding({ left: 11, right: 11 })
          }
          FormBox({ label: '备注' }) {
            TextInput({ placeholder: '可选', text: this.note })
              .onChange((v: string) => { this.note = v; })
              .fontSize(12).height(36)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
              .border({ width: 1, color: tk(this.dark, 'line') })
              .padding({ left: 11, right: 11 })
          }

          Column({ space: 11 }) {
            FormBox({ label: '分类' }) {
              PickerBox({
                text: areaLabel(this.area),
                options: ['工作', '副业', '自媒体', '学习', '生活'],
                onPick: (i: number) => { this.area = AREAS[i]; }
              })
            }
            FormBox({ label: '优先级' }) {
              PickerBox({
                text: this.priorityText(),
                options: PRIORITY_LABELS,
                onPick: (i: number) => { this.priority = PRIORITIES[i]; }
              })
            }
          }
          .width('100%')

          Column({ space: 11 }) {
            FormBox({ label: '项目' }) {
              PickerBox({
                text: this.projText(),
                options: this.projNames(),
                onPick: (i: number) => {
                  this.projectId = i === 0 ? -1 : Store.I.projects[i - 1].id;
                }
              })
            }
            FormBox({ label: '标签' }) {
              TextInput({ placeholder: '用逗号分隔', text: this.tags })
                .onChange((v: string) => { this.tags = v; })
                .fontSize(12).height(36)
                .placeholderFont({ size: 12 })
                .placeholderColor(tc(this.dark, '#A8B8C6', 1))
                .fontColor(tk(this.dark, 'text'))
                .caretColor(tk(this.dark, 'brand'))
                .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
                .border({ width: 1, color: tk(this.dark, 'line') })
                .padding({ left: 11, right: 11 })
            }
          }
          .width('100%')

          FormBox({ label: '状态' }) {
            SegTabs({
              options: ['待办', '进行中', '已完成'],
              sel: this.statusIndex(),
              onPick: (i: number) => { this.status = STATUSES[i]; }
            })
          }

          Column({ space: 11 }) {
            FormBox({ label: '截止时间' }) {
              DateBox({
                text: this.dueText(),
                muted: this.dueDate.length === 0,
                icon: 'calendar',
                onTap: () => { this.pickDate(this.dueDate, (v: string) => { this.dueDate = v; }); }
              })
            }
          Column() {
            FormBox({ label: '开始时间' }) {
              DateBox({
                text: this.startText(),
                muted: this.startAt.length === 0,
                icon: 'clock',
                onTap: () => { this.pickDateTime(this.startAt, (v: string) => { this.startAt = v; }); }
              })
            }
          }
          .width('100%')

            FormBox({ label: '预计分钟' }) {
              TextInput({ placeholder: '可选', text: this.estMin })
                .onChange((v: string) => { this.estMin = v; })
                .type(InputType.Number)
                .fontSize(12).height(36)
                .placeholderFont({ size: 12 })
                .placeholderColor(tc(this.dark, '#A8B8C6', 1))
                .fontColor(tk(this.dark, 'text'))
                .caretColor(tk(this.dark, 'brand'))
                .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
                .border({ width: 1, color: tk(this.dark, 'line') })
                .padding({ left: 11, right: 11 })
            }
          }
          .width('100%')

          HintLine({ text: '截止时间留空 = 长期任务，一直挂着，不会算逾期。开始时间留空就自动按「创建时间」推；截止时间已经过去的话，就从截止那天算起。' })

          Column({ space: 11 }) {
            FormBox({ label: '重复', icon: 'undo' }) {
              PickerBox({
                text: RULE_LABELS[this.ruleIndex()],
                options: RULE_LABELS,
                onPick: (i: number) => { this.rule = RULE_KEYS[i]; }
              })
            }
          }
          .width('100%')

          Column() {
            FormBox({ label: '关联日程', icon: 'calendar' }) {
              PickerBox({
                text: this.linkEventText(),
                options: this.linkEventLabels,
                onPick: (i: number) => { this.linkEventId = i >= 0 && i < this.linkEventIds.length ? this.linkEventIds[i] : -1; }
              })
            }
          }
          .width('100%')

          if (this.rule !== 'none') {
            HintLine({ text: '重复的任务勾完后，会自动把下一次排到往后一格；原来那条做完就收走了，不占位置、不计入统计（「全部」页里还能找到它）。' })
          }

          if (this.editingId > 0) {
            this.noteLinks()
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 11, bottom: 18 })
        .alignItems(HorizontalAlign.Start)
      }
      .onScrollEdge(onEdgeScrolled)
      .onWillScroll(onEdgeWillScroll)
      .edgeEffect(EdgeEffect.Spring)
      .constraintSize({ maxHeight: R.sheetBodyH() })
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)

      if (this.err.length > 0) {
        Column() {
          FormErr({ msg: this.err })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 8 })
      }

      SheetActs({
        primaryText: '保存',
        secondaryText: '取消',
        dangerText: this.editingId > 0 ? '删除' : '',
        busy: this.busy,
        onPrimary: () => { this.save(); },
        onSecondary: () => { this.onCancel(); },
        onDanger: () => { this.remove(); }
      })
    }
    .width('100%')
    .backgroundColor(tk(this.dark, 'card'))
    .borderRadius(22)
  }

  private statusIndex(): number {
    for (let i = 0; i < STATUSES.length; i++) {
      if (STATUSES[i] === this.status) { return i; }
    }
    return 0;
  }
}
