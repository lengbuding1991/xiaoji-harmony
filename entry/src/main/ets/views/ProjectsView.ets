// 项目进度
// 对齐「个人工作台」ProjectsApp.tsx：page-head → 项目卡列表（色点 + 名称 + 完成度条 + 备注
// + 展开看任务 / 最近记下的）→ 新建项目走 sheet（名字 + 颜色 + 目标日）。
import { Store } from '../store/Store';
import { areaLabel, C, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { SheetHead, FormBox, DateBox, FormErr, SheetActs } from '../components/FormKit';
import { Repo } from '../db/Repo';
import { Project, ProjectCreate, ProjectUpdate, Task, Note } from '../api/Types';
import { TopBar } from '../components/TopBar';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { SheetFrame } from '../components/SheetFrame';
import { R } from '../utils/Responsive';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';


/** 领域胶囊（新建项目时选「属于哪一块」） */
interface AreaChoice {
  key: string;
  label: string;
  color: string;
}

@Component
export struct ProjectsView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tick: number = 0;
  // v4.6：宽屏档位（宽屏时弹层限宽）
  @StorageLink('wb_layout') layoutMode: number = 0;
  @State tasks: Task[] = [];
  // v4.5：ArkUI V1 只刷新「表达式里直接读过 state」的节点 ⇒ 计数进 @State
  @State kUnassigned: number = 0;
  @State notes: Note[] = [];
  @State projects: Project[] = [];
  @State openId: number = -1;
  @State showNew: boolean = false;
  @State editId: number = -1;
  @State showArchived: boolean = false;
  onNavigate: (page: string) => void = () => {};
  @State newName: string = '';
  @State newColor: string = '#9B8AE6';
  @State newNote: string = '';
  @State newTarget: string = '';
  // v4.4：以前新建项目领域写死 'work'，所有项目都归「工作」
  @State newArea: string = 'work';
  @State busy: boolean = false;
  @State newErr: string = '';
  private unsub: () => void = () => {};
  // 新建/编辑项目时的领域胶囊
  private areaChoices: AreaChoice[] = [
    { key: 'work', label: '工作', color: '#1A6499' },
    { key: 'side', label: '副业', color: '#6650C8' },
    { key: 'media', label: '内容', color: '#A54A7A' },
    { key: 'study', label: '学习', color: '#0F6E58' },
    { key: 'life', label: '生活', color: '#8A5A0F' }
  ];

  private recalc(): void {
    this.kUnassigned = this.unassignedCount();
  }

  /** v4.6：宽屏？ */
  private wideMode(): boolean {
    return this.layoutMode >= 1;
  }

  private syncStore(): void {
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.projects = Store.I.projects;
    this.recalc();
  }

  private readonly palette: string[] = [
    '#1A6499', '#6650C8', '#A54A1E', '#14765F', '#8A5A0F', '#12706B', '#6F5FC4', '#A54A7A'
  ];

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  private pct(p: Project): number {
    return p.total === 0 ? 0 : Math.round(p.done * 100 / p.total);
  }

  private tasksOf(p: Project): Task[] {
    return this.tasks.filter((t: Task) => t.project_id === p.id);
  }

  private notesOf(p: Project): Note[] {
    return this.notes.filter((n: Note) => n.project_id === p.id).slice(0, 3);
  }

  private weekDone(p: Project): number {
    const ws: string = D.weekStart();
    let n = 0;
    for (const t of this.tasks) {
      if (t.project_id !== p.id) { continue; }
      if (t.status !== 'done' || t.done_at === null) { continue; }
      if (D.dateOf(t.done_at) >= ws) { n += 1; }
    }
    return n;
  }

  private dueText(p: Project): string {
    if (p.target_date === null || p.target_date.length < 10) { return ''; }
    const d = D.parse(p.target_date);
    const days: number = D.diffDays(d, new Date());
    if (days < 0) { return `已超期 ${-days} 天`; }
    if (days === 0) { return '就是今天'; }
    return `还剩 ${days} 天`;
  }

  private dueTone(p: Project): string {
    // v4.21：这三个色直接当白卡上的字色用，按 >=4.55:1 重算
    if (p.target_date === null || p.target_date.length < 10) { return '#52697E'; }
    const days: number = D.diffDays(D.parse(p.target_date), new Date());
    if (days < 0) { return '#A64B2E'; }
    if (days <= 3) { return '#885E20'; }
    return '#52697E';
  }

  private startNew(): void {
    this.editId = -1;
    this.newName = '';
    this.newNote = '';
    this.newTarget = '';
    this.newColor = '#9B8AE6';
    this.newArea = 'work';
    this.newErr = '';
    this.showNew = true;
  }

  private startEdit(p: Project): void {
    this.editId = p.id;
    this.newName = p.name;
    this.newNote = p.note;
    this.newTarget = p.target_date !== null ? p.target_date : '';
    this.newColor = p.color;
    this.newArea = p.area;
    this.newErr = '';
    this.showNew = true;
  }

  private async add(): Promise<void> {
    const name: string = this.newName.trim();
    if (name.length === 0) { this.newErr = '先写个项目名'; return; }
    this.busy = true;
    this.newErr = '';
    if (this.editId > 0) {
      const body: ProjectUpdate = {
        name: name,
        color: this.newColor,
        note: this.newNote,
        area: this.newArea,
        target_date: this.newTarget.length >= 10 ? this.newTarget : null
      } as ProjectUpdate;
      try {
        await Repo.patchProject(this.editId, body);
        await Store.I.reloadProjects();
        this.busy = false;
        this.showNew = false;
        this.editId = -1;
        toast(this.getUIContext(), '项目已更新');
      } catch (e) {
        this.busy = false;
        this.newErr = (e as Error).message;
      }
      return;
    }
    const body: ProjectCreate = {
      name: name,
      color: this.newColor,
      note: this.newNote,
      area: this.newArea,
      target_date: this.newTarget.length >= 10 ? this.newTarget : null
    } as ProjectCreate;
    const ok: boolean = await Store.I.addProject(body);
    this.busy = false;
    if (ok) {
      this.showNew = false;
      this.newErr = '';
      toast(this.getUIContext(), '项目建好了');
    } else {
      this.newErr = Store.I.lastError.length > 0 ? Store.I.lastError : '没建成，再试一次';
    }
  }

  /** 归档 / 恢复（对齐工作台 toggleArchive） */
  private async toggleArchive(p: Project): Promise<void> {
    const next: string = p.status === 'archived' ? 'active' : 'archived';
    const body: ProjectUpdate = { status: next } as ProjectUpdate;
    try {
      await Repo.patchProject(p.id, body);
      await Store.I.reloadProjects();
      toast(this.getUIContext(), next === 'archived' ? '已归档' : '已恢复');
    } catch (e) {
      toast(this.getUIContext(), (e as Error).message);
    }
  }

  private activeProjects(): Project[] {
    return this.projects.filter((p: Project) => p.status !== 'archived');
  }

  private archivedProjects(): Project[] {
    return this.projects.filter((p: Project) => p.status === 'archived');
  }

  private unassignedCount(): number {
    return this.tasks.filter((t: Task) => t.project_id === null).length;
  }

  /** 删除项目：先弹自绘确认框（项目下的任务会变成「未归类」） */
  private remove(p: Project): void {
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '删除这个项目？',
      `「${p.name}」会被移除，项目下的任务会变成「未归类」（任务本身不会删）。`, '删除',
      () => { this.doRemove(p); });
  }

  /** 确认之后才真的删 */
  private async doRemove(p: Project): Promise<void> {
    try {
      await Repo.deleteProject(p.id);
      await Store.I.reloadProjects();
      await Store.I.reloadTasks();
      toast(this.getUIContext(), '删掉了');
    } catch (e) {
      toast(this.getUIContext(), (e as Error).message);
    }
  }

  private async archive(p: Project): Promise<void> {
    try {
      const body: ProjectUpdate = { note: p.note } as ProjectUpdate;
      await Repo.patchProject(p.id, body);
      await Store.I.reloadProjects();
    } catch (e) {
      toast(this.getUIContext(), (e as Error).message);
    }
  }

  // 三个并排小按钮（对齐 .pj-acts button：flex 1、居中、gap 4、高 27、radius 9、白底描边）
  @Builder pjAct(icon: string, label: string, danger: boolean, cb: () => void) {
    Row({ space: 4 }) {
      SymbolGlyph(sym(icon))
        .fontSize(14)
        .fontColor([danger ? tc(this.dark, '#B06A5C', 1) : tc(this.dark, '#7C8F9F', 1)])
      Text(label).fontSize(10).fontColor(danger ? tc(this.dark, '#B06A5C', 1) : tc(this.dark, '#7C8F9F', 1))
    }
    .layoutWeight(1)
    .height(27)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(9)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .border({ width: 1, color: tk(this.dark, 'line') })
    .onClick(cb)
  }

  // ── 视图 ──
  @Builder projCard(p: Project) {
    Column({ space: 9 }) {
      // 头部：色点 + 名字 + 百分比
      Row({ space: 9 }) {
        Row().width(9).height(9).borderRadius(5).backgroundColor(p.color).flexShrink(0)
        Column({ space: 2 }) {
          Text(p.name)
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#2C4257', 1))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Row({ space: 0 }) {
            Text(`${areaLabel(p.area)} · ${p.total} 件任务`)
              .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1))
            if (this.weekDone(p) > 0) {
              Text(' · 本周完成 ')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1))
              Text(`${this.weekDone(p)}`)
                .fontSize(9.5).fontColor(tc(this.dark, '#17A8A4', 1)).fontWeight(FontWeight.Bold)
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(`${this.pct(p)}%`)
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5C7086', 1)).flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.openId = this.openId === p.id ? -1 : p.id; })

      // 进度条
      Row() {
        Row()
          .height('100%')
          .width(`${this.pct(p)}%`)
          .borderRadius(99)
          .backgroundColor(p.color)
      }
      .width('100%').height(5).borderRadius(99).backgroundColor(tc(this.dark, '#EEF5FA', 0))
      .alignItems(VerticalAlign.Center)

      if (p.note.length > 0) {
        Text(p.note).fontSize(10).fontColor(tc(this.dark, '#8FA2B3', 1)).width('100%')
      }

      if (this.dueText(p).length > 0) {
        Row({ space: 5 }) {
          Text('目标日').fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
          Text(p.target_date !== null ? D.slashMd(D.parse(p.target_date)) : '')
            .fontSize(9).fontColor(tc(this.dark, '#B6C8D6', 1))
          Text(this.dueText(p)).fontSize(10).fontColor(this.dueTone(p)).fontWeight(FontWeight.Medium)
          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      // 三个并排按钮（对齐工作台 .pj-acts：编辑 / 归档 / 删除）
      Row({ space: 5 }) {
        // v4.4：第一个按钮恒为「编辑」—— 以前归档项目两个按钮都写「恢复」，
        // 而且归档后就再也编辑不了了。
        this.pjAct('pen', '编辑', false, () => { this.startEdit(p); })
        this.pjAct('archive', p.status === 'archived' ? '恢复' : '归档', false, () => { this.toggleArchive(p); })
        this.pjAct('trash', '删除', true, () => { this.remove(p); })
      }
      .width('100%')
      .margin({ top: 1 })

      // 展开：任务 + 灵感
      if (this.openId === p.id) {
        Column({ space: 6 }) {
          Divider().color('#EAF2F9').strokeWidth(1)

          if (this.tasksOf(p).length === 0) {
            Text('这个项目还没有任务。去任务面板把任务归到它下面。')
              .fontSize(10).fontColor(tc(this.dark, '#B6C8D6', 1)).width('100%')
          } else {
            ForEach(this.tasksOf(p), (t: Task) => {
              Row({ space: 7 }) {
                Row() {
                  if (t.status === 'done') {
                    // v4.23：fs14 的勾盒子 14x14vp，圆放大到 16vp 才装得下
                    SymbolGlyph(sym('check')).fontSize(14).fontColor([tkInk(this.dark, 'study')])
                  }
                }
                .width(16).height(16).borderRadius(8)
                .backgroundColor(t.status === 'done' ? tk(this.dark, 'brandSoft') : tk(this.dark, 'card'))
                .border({ width: 1.5, color: t.status === 'done' ? tk(this.dark, 'study') : tc(this.dark, '#DDE9F3', 2) })
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .flexShrink(0)
                .onClick(() => { Store.I.toggleTask(t.id).catch(() => {}); })

                Text(t.title)
                  .fontSize(10.5)
                  .fontColor(t.status === 'done' ? tc(this.dark, '#A8B8C6', 1) : tc(this.dark, '#4E6579', 1))
                  .decoration({ type: t.status === 'done' ? TextDecorationType.LineThrough : TextDecorationType.None, color: '#A8B8C6' })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (t.due_date !== null) {
                  Text(D.slashMd(D.parse(t.due_date))).fontSize(9).fontColor(tc(this.dark, '#B6C8D6', 1)).flexShrink(0)
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }, (t: Task) => `pt-${t.id}-${t.status}-${this.tick}`)
          }

          if (this.notesOf(p).length > 0) {
            Column({ space: 3 }) {
              Text('最近记下的').fontSize(10).fontColor(tc(this.dark, '#A8B8C6', 1)).fontWeight(FontWeight.Medium).width('100%')
              ForEach(this.notesOf(p), (n: Note) => {
                Row() {
                  Text(n.title.length > 0 ? n.title : '(无标题)')
                    .fontSize(11).fontColor(tc(this.dark, '#4E6C86', 1))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  Text(D.short(D.dateOf(n.updated_at))).fontSize(9).fontColor(tc(this.dark, '#B6C8D6', 1)).flexShrink(0)
                }
                .width('100%')
              }, (n: Note) => `pn-${n.id}-${this.tick}`)
            }
            .width('100%')
            .margin({ top: 2 })
          }

          Text('收起')
            .fontSize(9.5).fontColor(tc(this.dark, '#7C8F9F', 1)).width('100%').textAlign(TextAlign.Center)
            .padding({ top: 6, bottom: 6 }).borderRadius(8)
            .backgroundColor(tk(this.dark, 'card')).border({ width: 1, color: tk(this.dark, 'line') })
            .onClick(() => { this.openId = -1; })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: 15, right: 15, top: 14, bottom: 14 })
    .borderRadius(18)
    .backgroundColor(tk(this.dark, 'card'))
    .border({ width: 1, color: this.openId === p.id ? tk(this.dark, 'brandLine') : tk(this.dark, 'cardBorder') })
    .shadow(cardShadow2())
    .margin({ bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder newSheetBody() {
    Column() {
      Scroll() {
        Column({ space: 11 }) {
          SheetHead({ title: this.editId > 0 ? '编辑项目' : '新建项目', sub: this.editId > 0 ? '改完直接保存。' : '起个名字，颜色随便挑一个。' })

          FormBox({ label: '项目名' }) {
            TextInput({ placeholder: '比如：个人网站改版', text: this.newName })
              .fontSize(12).height(36)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
              .border({ width: 1, color: tk(this.dark, 'line') })
              .padding({ left: 11, right: 11 })
              .onChange((v: string) => { this.newName = v; })
          }

          FormBox({ label: '一句话说明' }) {
            TextArea({ placeholder: '可选', text: this.newNote })
              .fontSize(12)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .constraintSize({ minHeight: 62 })
              .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
              .border({ width: 1, color: tk(this.dark, 'line') })
              .padding(10)
              .onChange((v: string) => { this.newNote = v; })
          }

          FormBox({ label: '属于哪一块' }) {
            Row({ space: 8 }) {
              ForEach(this.areaChoices, (a: AreaChoice) => {
                Text(a.label)
                  .fontSize(11)
                  .fontColor(this.newArea === a.key ? onFill(this.dark) : tc(this.dark, '#5E7183', 1))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(999)
                  .backgroundColor(this.newArea === a.key ? a.color : tc(this.dark, '#F4F9FE', 0))
                  .onClick(() => { this.newArea = a.key; })
              }, (a: AreaChoice) => `pa-${a.key}`)
            }
            .width('100%')
          }

          FormBox({ label: '颜色' }) {
            Row({ space: 8 }) {
              ForEach(this.palette, (c: string) => {
                Row()
                  .width(26).height(26).borderRadius(13)
                  .backgroundColor(c)
                  .border({ width: 2, color: this.newColor === c ? (this.dark ? '#E8EFF7' : '#2C4257') : '#00000000' })
                  .onClick(() => { this.newColor = c; })
              }, (c: string) => `pc-${c}`)
            }
            .width('100%')
          }

          FormBox({ label: '目标日（可选）' }) {
            DateBox({
              text: this.newTarget.length > 0 ? this.newTarget : '选一个目标日',
              muted: this.newTarget.length === 0,
              icon: 'calendar',
              onTap: () => {
                let sel: Date = new Date();
                if (this.newTarget.length >= 10) { sel = D.parse(this.newTarget); }
                this.getUIContext().showDatePickerDialog({
                  start: new Date(2020, 0, 1),
                  end: new Date(2035, 11, 31),
                  selected: sel,
                  onDateAccept: (d: Date) => { this.newTarget = D.key(d); }
                });
              }
            })
          }

          FormErr({ msg: this.newErr })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 18 })
        .alignItems(HorizontalAlign.Start)
      }
      .onScrollEdge(onEdgeScrolled)
      .onWillScroll(onEdgeWillScroll)
      .edgeEffect(EdgeEffect.Spring)
      .constraintSize({ maxHeight: R.sheetBodyH() })
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)

      SheetActs({
        primaryText: this.editId > 0 ? '保存' : '建项目',
        secondaryText: '取消',
        busy: this.busy,
        onPrimary: () => { this.add(); },
        onSecondary: () => { this.showNew = false; }
      })
    }
    .width('100%')
    .backgroundColor(tk(this.dark, 'card'))
    .borderRadius(22)
  }


  /** v4.6：宽屏（平板/折叠屏）走「遮罩 + 居中卡片」，窄屏还是底部抽屉 */
  @Builder newSheet() {
    SheetFrame({
      wide: this.wideMode(),
      onClose: () => { this.showNew = false; this.editId = -1; },
      content: () => { this.newSheetBody(); }
    })
  }

  @Builder pageTop() {
    TopBar({
      primaryText: '新建项目',
      onPrimary: () => { this.startNew(); },
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
        Row({ space: 10 }) {
          Column({ space: 5 }) {
            Text('PROJECTS · 项目进度').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
            Text('手上的事，分成几摊。')
              .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
            Text('每个项目一个进度条，做久了能看出哪摊在推进、哪摊在拖。')
              .fontSize(11).fontColor(tk(this.dark, 'textSub'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .padding({ top: 14, bottom: 14 })

        if (this.activeProjects().length === 0 && this.archivedProjects().length === 0) {
          Column({ space: 7 }) {
            SymbolGlyph(sym('target')).fontSize(28).fontColor([tc(this.dark, '#C7D8E4', 1)])
            Text('还没有项目').fontSize(14).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5C7086', 1))
            Text('把相关的任务归到一个项目里，比如「小记 v1 上线」「11 月副业」。')
              .fontSize(11).fontColor(tc(this.dark, '#A8B8C6', 1))
              .textAlign(TextAlign.Center)
            Text('点右上角「新建项目」开始。')
              .fontSize(11).fontColor(tc(this.dark, '#A8B8C6', 1))
              .textAlign(TextAlign.Center)
            Text('新建第一个项目')
              .fontSize(11).fontColor(onFill(this.dark))
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(S.radiusBtn)
              .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
              .margin({ top: 4 })
              .onClick(() => { this.startNew(); })
          }
          .width('100%')
          .padding({ top: 34, bottom: 34 })
          .borderRadius(S.radiusCard)
          .border({ width: 1, color: tc(this.dark, tc(this.dark, '#DDE9F3', 2), 2), style: BorderStyle.Dashed })
          .backgroundColor(this.dark ? 'rgba(24,34,46,0.6)' : 'rgba(255,255,255,0.6)')
          .alignItems(HorizontalAlign.Center)
        } else {
          ForEach(this.activeProjects(), (p: Project) => {
            this.projCard(p)
          }, (p: Project) => `pj-${p.id}-${p.done}-${p.total}-${this.openId}-${p.status}-${this.tick}`)

          if (this.archivedProjects().length > 0) {
            Text('已归档')
              .fontSize(10.5).fontColor(tc(this.dark, '#A8B8C6', 1)).fontWeight(FontWeight.Medium)
              .letterSpacing(0.4)
              .width('100%')
              .margin({ top: 8, bottom: 4 })
            ForEach(this.archivedProjects(), (p: Project) => {
              this.projCard(p)
            }, (p: Project) => `pja-${p.id}-${p.done}-${p.total}-${this.openId}-${p.status}`)
          }
        }

        if (this.projects.length > 0 && this.unassignedCount() > 0) {
          Text(`还有 ${this.kUnassigned} 件任务没归到项目里。在任务面板编辑任务时选一下项目就行。`)
            .fontSize(10.5)
            .fontColor(tc(this.dark, '#A8B8C6', 1))
            .width('100%')
            .margin({ top: 6, bottom: S.pageBottom })
        }
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
    .bindSheet($$this.showNew, this.newSheet(), {
      height: this.wideMode() ? '100%' : SheetSize.FIT_CONTENT,
      dragBar: !this.wideMode(),
      showClose: false,
      backgroundColor: Color.Transparent,   // 面板透明，弹层内容自己带圆角白底
      width: '100%'})
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
}

function cardShadow2(): ShadowOptions {
  return { radius: 30, color: 'rgba(37,84,133,0.07)', offsetX: 0, offsetY: 10 };
}
