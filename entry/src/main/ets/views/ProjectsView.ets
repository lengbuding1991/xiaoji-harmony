// 我的项目
// 对齐「个人工作台」ProjectsApp.tsx：page-head → 项目卡列表（色点 + 名称 + 完成度条 + 备注
// + 展开看任务 / 最近记下的）→ 新建项目走 sheet（名字 + 颜色 + 目标日）。
import { Store } from '../store/Store';
import { S, areaLabel, brandGradient, misc, onFill, paletteList, tc, tk, tkInk } from '../utils/Theme';
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
  @StorageLink('wb_pal') pal: number = 0;
  @State tick: number = 0;
  // v4.6：宽屏档位（宽屏时弹层限宽）
  @StorageLink('wb_layout') layoutMode: number = 0;
  // v5.17：宽屏列数（>1180vp 三列 / >820vp 两列 / 更窄一列）。
  //   R.cols() 读的是 AppStorage，改窗口大小时不会自己触发本页重画 ⇒ 这里挂一个 @StorageLink，
  //   窗口宽度一变（旋转、分屏、拖窗口）本页就会重画，栅格列数跟着变。
  @StorageLink('wb_cols') cols: number = 1;
  @State tasks: Task[] = [];
  // v4.5：ArkUI V1 只刷新「表达式里直接读过 state」的节点 ⇒ 计数进 @State
  @State kUnassigned: number = 0;
  @State notes: Note[] = [];
  @State projects: Project[] = [];
  @State openId: number = -1;
  @State showNew: boolean = false;
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
      this.showNew = true;
    }
  }

  private closeSheet(): void {
    this.showNew = false;
    this.wideOpen = false;
    AppStorage.setOrCreate<boolean>('wb_fab_hide', false);
  }

  /** v4.26：宽屏时铺在页面最上层的遮罩 + 居中卡片 */
  @Builder
  wideOverlay() {
    if (this.wideMode() && this.wideOpen) {
      this.newSheet()
    }
  }

  @State editId: number = -1;
  @State showArchived: boolean = false;
  onNavigate: (page: string) => void = () => {};
  // v5.17：二级页返回（Index 传进来的）
  onBack: () => void = () => {};
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
  /** v5.7：领域色跟着配色方案走 */
  private areaChoices(pal: number): AreaChoice[] {
    return [
      { key: 'work', label: '工作', color: tk(pal, 'work') },
      { key: 'side', label: '副业', color: tk(pal, 'side') },
      { key: 'media', label: '内容', color: tk(pal, 'media') },
      { key: 'study', label: '学习', color: tk(pal, 'study') },
      { key: 'life', label: '生活', color: tk(pal, 'life') }
    ];
  }

  private recalc(): void {
    this.kUnassigned = this.unassignedCount();
  }

  /** v4.6：宽屏？ */
  private wideMode(): boolean {
    return this.layoutMode >= 1;
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

  private syncStore(): void {
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.projects = Store.I.projects;
    this.recalc();
  }

  /** v5.7：项目配色盘跟着配色方案走 */
  private projectPalette(pal: number): string[] {
    return paletteList(pal, 'project8');
  }

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
    if (days < 0) { return '#A83440'; }
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
    this.openSheet();
  }

  private startEdit(p: Project): void {
    this.editId = p.id;
    this.newName = p.name;
    this.newNote = p.note;
    this.newTarget = p.target_date !== null ? p.target_date : '';
    this.newColor = p.color;
    this.newArea = p.area;
    this.newErr = '';
    this.openSheet();
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
        this.closeSheet();
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
      this.closeSheet();
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

  // 三个并排小按钮（对齐 .pj-acts button：flex 1、居中、gap 4、radius 9、白底描边）
  // v5.15 可访问性：原来高 27 ⇒ 撑到 40
  @Builder pjAct(icon: string, label: string, danger: boolean, cb: () => void) {
    Row({  space: S.spaceSm  }) {
      SymbolGlyph(sym(icon))
        .fontSize(S.cardTitleSize)
        .fontColor([danger ? tc(this.pal, '#B06A5C', 1) : tc(this.pal, '#7C8F9F', 1)])
      Text(label).fontSize(S.subSize).fontColor(danger ? tc(this.pal, '#B06A5C', 1) : tc(this.pal, '#7C8F9F', 1))
    }
    .layoutWeight(1)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(S.radiusSm)
    .backgroundColor(tc(this.pal, '#FFFFFF', 0))
    .border({ width: 1, color: tk(this.pal, 'line') })
    .onClick(cb)
    .accessibilityText(label)
  }

  // ── 视图 ──
  @Builder projCard(p: Project) {
    Column({  space: S.spaceXl  }) {
      // 头部：色点 + 名字 + 百分比
      Row({  space: S.spaceXl  }) {
        Row().width(9).height(9).borderRadius(S.radiusXs).backgroundColor(p.color).flexShrink(0)
        Column({  space: S.spaceXs  }) {
          Text(p.name)
            .fontSize(S.midSize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#2C4257', 1))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Row({  space: 0  }) {
            Text(`${areaLabel(p.area)} · ${p.total} 件任务`)
              .fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
            if (this.weekDone(p) > 0) {
              Text(' · 本周完成 ')
                .fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
              Text(`${this.weekDone(p)}`)
                .fontSize(S.tinySize).fontColor(tc(this.pal, '#17A8A4', 1)).fontWeight(FontWeight.Bold)
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(`${this.pct(p)}%`)
          .fontSize(S.smallSize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#5C7086', 1)).flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.openId = this.openId === p.id ? -1 : p.id; })

      // 进度条
      Row() {
        Row()
          .height('100%')
          .width(`${this.pct(p)}%`)
          .borderRadius(S.radiusPill)
          .backgroundColor(p.color)
      }
      .width('100%').height(5).borderRadius(S.radiusPill).backgroundColor(tc(this.pal, '#EEF5FA', 0))
      .alignItems(VerticalAlign.Center)

      if (p.note.length > 0) {
        Text(p.note).fontSize(S.subSize).fontColor(tc(this.pal, '#8FA2B3', 1)).width('100%')
      }

      if (this.dueText(p).length > 0) {
        Row({  space: S.spaceMd  }) {
          Text('目标日').fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
          Text(p.target_date !== null ? D.md(p.target_date) : '')
            .fontSize(S.tinySize).fontColor(tc(this.pal, '#B6C8D6', 1))
          Text(this.dueText(p)).fontSize(S.subSize).fontColor(this.dueTone(p)).fontWeight(FontWeight.Medium)
          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      // 三个并排按钮（对齐工作台 .pj-acts：编辑 / 归档 / 删除）
      Row({  space: S.spaceMd  }) {
        // v4.4：第一个按钮恒为「编辑」—— 以前归档项目两个按钮都写「恢复」，
        // 而且归档后就再也编辑不了了。
        this.pjAct('pen', '编辑', false, () => { this.startEdit(p); })
        this.pjAct('archive', p.status === 'archived' ? '恢复' : '归档', false, () => { this.toggleArchive(p); })
        this.pjAct('trash', '删除', true, () => { this.remove(p); })
      }
      .width('100%')
      .margin({  top: S.spaceXs  })

      // 展开：任务 + 灵感
      if (this.openId === p.id) {
        Column({  space: S.spaceMd  }) {
          Divider().color('#EAF2F9').strokeWidth(1)

          if (this.tasksOf(p).length === 0) {
            Text('这个项目还没有任务。去任务面板把任务归到它下面。')
              .fontSize(S.subSize).fontColor(tc(this.pal, '#B6C8D6', 1)).width('100%')
          } else {
            ForEach(this.tasksOf(p), (t: Task) => {
              Row({  space: S.spaceLg  }) {
                // v5.15 可访问性：勾选框原来只有 16×16 ⇒ 外层套 40×40 的透明热区，勾选框本身不变
                Row() {
                  Row() {
                    if (t.status === 'done') {
                      // v4.23：fs14 的勾盒子 14x14vp，圆放大到 16vp 才装得下
                      SymbolGlyph(sym('check')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'study')])
                    }
                  }
                  .width(16).height(16).borderRadius(S.radiusSm)
                  .backgroundColor(t.status === 'done' ? tk(this.pal, 'brandSoft') : tk(this.pal, 'card'))
                  .border({ width: 1.5, color: t.status === 'done' ? tk(this.pal, 'study') : tc(this.pal, '#DDE9F3', 2) })
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                }
                .width(40).height(40)
                .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
                .flexShrink(0)
                // v5.14：以前 `.catch(() => {})` 是死代码（Store 自己吞掉了异常），
                //   改成失败会静默。现在按返回值提示。
                .onClick(() => {
                  Store.I.toggleTask(t.id).then((ok: boolean) => {
                    if (!ok) { toast(this.getUIContext(), '状态没改成，再试一次'); }
                  });
                })
                .accessibilityText(t.status === 'done' ? `把任务 ${t.title} 改回待办` : `把任务 ${t.title} 标记为已完成`)

                Text(t.title)
                  .fontSize(S.subSize)
                  .fontColor(t.status === 'done' ? tc(this.pal, '#A8B8C6', 1) : tc(this.pal, '#4E6579', 1))
                  .decoration({ type: t.status === 'done' ? TextDecorationType.LineThrough : TextDecorationType.None, color: '#A8B8C6' })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (t.due_date !== null) {
                  Text(D.md(t.due_date)).fontSize(S.tinySize).fontColor(tc(this.pal, '#B6C8D6', 1)).flexShrink(0)
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }, (t: Task) => `pt-${t.id}-${t.status}-${this.tick}`)
          }

          if (this.notesOf(p).length > 0) {
            Column({  space: S.spaceSm  }) {
              Text('最近记下的').fontSize(S.subSize).fontColor(tc(this.pal, '#A8B8C6', 1)).fontWeight(FontWeight.Medium).width('100%')
              ForEach(this.notesOf(p), (n: Note) => {
                Row() {
                  Text(n.title.length > 0 ? n.title : '(无标题)')
                    .fontSize(S.labelSize).fontColor(tc(this.pal, '#4E6C86', 1))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  Text(D.md(D.dateOf(n.updated_at))).fontSize(S.tinySize).fontColor(tc(this.pal, '#B6C8D6', 1)).flexShrink(0)
                }
                .width('100%')
              }, (n: Note) => `pn-${n.id}-${this.tick}`)
            }
            .width('100%')
            .margin({  top: S.spaceXs  })
          }

          // v5.15 可访问性：「收起」原来只有 ~21 高 ⇒ 撑到 40
          Text('收起')
            .fontSize(S.tinySize).fontColor(tc(this.pal, '#7C8F9F', 1)).width('100%').textAlign(TextAlign.Center)
            .height(40)
            .borderRadius(S.radiusSm)
            .backgroundColor(tk(this.pal, 'card')).border({ width: 1, color: tk(this.pal, 'line') })
            .onClick(() => { this.openId = -1; })
            .accessibilityText('收起这个项目')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding({  left: 15, right: 15, top: S.space3Xl, bottom: S.space3Xl  })
    .borderRadius(S.radiusCard)
    .backgroundColor(tk(this.pal, 'card'))
    .border({ width: 1, color: this.openId === p.id ? tk(this.pal, 'brandLine') : tk(this.pal, 'cardBorder') })
    .shadow(cardShadow2())
    .margin({  bottom: S.space2Xl  })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder newSheetBody() {
    Column() {
      Scroll() {
        Column({  space: S.space2Xl  }) {
          SheetHead({ title: this.editId > 0 ? '编辑项目' : '新建项目', sub: this.editId > 0 ? '改完直接保存。' : '起个名字，颜色随便挑一个。' })

          FormBox({ label: '项目名' }) {
            TextInput({ placeholder: '比如：个人网站改版', text: this.newName })
              .fontSize(S.smallSize).height(36)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.pal, '#A8B8C6', 1))
              .fontColor(tk(this.pal, 'text'))
              .caretColor(tk(this.pal, 'brand'))
              .backgroundColor(tc(this.pal, '#F8FBFE', 0)).borderRadius(S.radiusBtn)
              .border({ width: 1, color: tk(this.pal, 'line') })
              .padding({  left: S.space2Xl, right: S.space2Xl  })
              .onChange((v: string) => { this.newName = v; })
          }

          FormBox({ label: '一句话说明' }) {
            TextArea({ placeholder: '可选', text: this.newNote })
              .fontSize(S.smallSize)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.pal, '#A8B8C6', 1))
              .fontColor(tk(this.pal, 'text'))
              .caretColor(tk(this.pal, 'brand'))
              .constraintSize({ minHeight: 62 })
              .backgroundColor(tc(this.pal, '#F8FBFE', 0)).borderRadius(S.radiusBtn)
              .border({ width: 1, color: tk(this.pal, 'line') })
              .padding(10)
              .onChange((v: string) => { this.newNote = v; })
          }

          FormBox({ label: '属于哪一块' }) {
            Row({  space: S.spaceLg  }) {
              ForEach(this.areaChoices(this.pal), (a: AreaChoice) => {
                // v5.15 可访问性：胶囊原来只有 ~23 高 ⇒ 外层套 40 高的透明热区，胶囊本身不变
                Row() {
                  Text(a.label)
                    .fontSize(S.labelSize)
                    .fontColor(this.newArea === a.key ? onFill(this.pal) : tc(this.pal, '#5E7183', 1))
                    .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceMd, bottom: S.spaceMd  })
                    .borderRadius(S.radiusPill)
                    .backgroundColor(this.newArea === a.key ? a.color : tc(this.pal, '#F4F9FE', 0))
                }
                .height(40)
                .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
                .onClick(() => { this.newArea = a.key; })
                .accessibilityText(`选 ${a.label}`)
              }, (a: AreaChoice) => `pa-${a.key}-${this.pal}`)
            }
            .width('100%')
          }

          FormBox({ label: '颜色' }) {
            Row({  space: S.spaceLg  }) {
              ForEach(this.projectPalette(this.pal), (c: string, i: number) => {
                // v5.15 可访问性：色块原来只有 26×26 ⇒ 外层套 40×40 的透明热区，色块本身不变
                Row() {
                  Row()
                    .width(26).height(26).borderRadius(S.radiusInner)
                    .backgroundColor(c)
                    .border({ width: 2, color: this.newColor === c ? '#2C4257' : '#00000000' })
                }
                .width(40).height(40)
                .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
                .onClick(() => { this.newColor = c; })
                .accessibilityText(`选第 ${i + 1} 个颜色`)
              }, (c: string) => `pc-${c}-${this.pal}`)
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
        .padding({  left: S.space5Xl, right: S.space5Xl, top: S.space5Xl  })
        .alignItems(HorizontalAlign.Start)
      }
        // v5.16：滚动时把右下角悬浮按钮藏起来（它正好压在内容上），停了就回来
        .onDidScroll((x: number, y: number) => { AppStorage.setOrCreate<boolean>('wb_scrolling', true); })
        .onScrollStop(() => { AppStorage.setOrCreate<boolean>('wb_scrolling', false); })
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
        onSecondary: () => { this.closeSheet(); }
      })
    }
    .width('100%')
    .backgroundColor(tk(this.pal, 'card'))
    .borderRadius(S.radiusSheet)
  }


  /** v4.6：宽屏（平板/折叠屏）走「遮罩 + 居中卡片」，窄屏还是底部抽屉 */
  @Builder newSheet() {
    SheetFrame({
      wide: this.wideMode(),
      onClose: () => { this.closeSheet(); this.editId = -1; },
      content: () => { this.newSheetBody(); }
    })
  }

  @Builder pageTop() {
    TopBar({
      backLabel: '返回',
      onBack: () => { this.onBack(); },
      primaryText: '新建项目',
      onPrimary: () => { this.startNew(); },
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  build() {
    Stack() {

      Scroll() {
        Column() {
          Text(`${this.tick}`).fontSize(S.hiddenSize).width(1).height(1).opacity(0)

          this.pageTop()

          // page-head
          Row({  space: S.spaceXl  }) {
            Column({  space: S.spaceMd  }) {
              Text('PROJECTS · 我的项目').fontSize(S.tinySize).fontColor(tc(this.pal, '#9DB0C1', 1)).letterSpacing(1.6)
              Text('手上的事，分成几摊。')
                .fontSize(S.sectionSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text')).letterSpacing(-0.2)
              Text('一个项目一条进度，看得出哪摊在推进。')
                .fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .padding({  top: S.spaceXl, bottom: S.spaceXl  })

          if (this.activeProjects().length === 0 && this.archivedProjects().length === 0) {
            Column({  space: S.spaceLg  }) {
              SymbolGlyph(sym('target')).fontSize(28).fontColor([tc(this.pal, '#C7D8E4', 1)])
              Text('还没有项目').fontSize(S.cardTitleSize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#5C7086', 1))
              Text('把相关的任务归到一个项目里，比如「小记 v1 上线」「11 月副业」。')
                .fontSize(S.labelSize).fontColor(tc(this.pal, '#A8B8C6', 1))
                .textAlign(TextAlign.Center)
              Text('点右上角「新建项目」开始。')
                .fontSize(S.labelSize).fontColor(tc(this.pal, '#A8B8C6', 1))
                .textAlign(TextAlign.Center)
              // v5.15 可访问性：「新建第一个项目」原来只有 ~27 高 ⇒ 撑到 40
              Text('新建第一个项目')
                .fontSize(S.labelSize).fontColor(onFill(this.pal))
                .height(40)
                .padding({  left: S.space4Xl, right: S.space4Xl  })
                .borderRadius(S.radiusBtn)
                .textAlign(TextAlign.Center)
                .linearGradient(brandGradient(this.pal))
                .margin({  top: S.spaceSm  })
                .onClick(() => { this.startNew(); })
                .accessibilityText('新建第一个项目')
            }
            .width('100%')
            .padding({  top: 34, bottom: 34  })
            .borderRadius(S.radiusCard)
            .border({ width: 1, color: tc(this.pal, tc(this.pal, '#DDE9F3', 2), 2), style: BorderStyle.Dashed })
            .backgroundColor('rgba(255,255,255,0.6)')
            .alignItems(HorizontalAlign.Center)
          } else {
            if (this.gridCols() >= 2) {
              // v5.17 宽屏：项目卡片铺 2~3 列（手机走下面的单列分支，排版跟以前一样）。
              GridRow({ columns: this.gridCols(), gutter: { x: S.gapLg, y: 0 } }) {
                ForEach(this.activeProjects(), (p: Project) => {
                  GridCol({ span: this.spanFor(1) }) {
                    Column() {
                      this.projCard(p)
                    }
                    .width('100%')
                  }
                }, (p: Project) => `pj-${p.id}-${p.done}-${p.total}-${this.openId}-${p.status}-${this.tick}`)
              }
              .width('100%')
            } else {
              ForEach(this.activeProjects(), (p: Project) => {
                this.projCard(p)
              }, (p: Project) => `pj-${p.id}-${p.done}-${p.total}-${this.openId}-${p.status}-${this.tick}`)
            }

            if (this.archivedProjects().length > 0) {
              Text('已归档')
                .fontSize(S.subSize).fontColor(tc(this.pal, '#A8B8C6', 1)).fontWeight(FontWeight.Medium)
                .letterSpacing(0.4)
                .width('100%')
                .margin({  top: S.spaceLg, bottom: S.spaceSm  })
              if (this.gridCols() >= 2) {
                GridRow({ columns: this.gridCols(), gutter: { x: S.gapLg, y: 0 } }) {
                  ForEach(this.archivedProjects(), (p: Project) => {
                    GridCol({ span: this.spanFor(1) }) {
                      Column() {
                        this.projCard(p)
                      }
                      .width('100%')
                    }
                  }, (p: Project) => `pja-${p.id}-${p.done}-${p.total}-${this.openId}-${p.status}`)
                }
                .width('100%')
              } else {
                ForEach(this.archivedProjects(), (p: Project) => {
                  this.projCard(p)
                }, (p: Project) => `pja-${p.id}-${p.done}-${p.total}-${this.openId}-${p.status}`)
              }
            }
          }

          if (this.projects.length > 0 && this.unassignedCount() > 0) {
            Text(`还有 ${this.kUnassigned} 件任务没归到项目里。在任务面板编辑任务时选一下项目就行。`)
              .fontSize(S.subSize)
              .fontColor(tc(this.pal, '#A8B8C6', 1))
              .width('100%')
              .margin({  top: S.spaceMd, bottom: R.bottomPad()  })
          }
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
      .align(Alignment.TopStart)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .constraintSize({ maxWidth: 1240 })
      // v5.0：页面底色改成透明，让 Index 根 Stack 上的大光斑透出来
      .backgroundColor(Color.Transparent)
      .edgeEffect(EdgeEffect.Spring)
      .bindSheet($$this.showNew, this.newSheet(), {
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
        this.newSheet()
      }
    }
    .width('100%')
    .height('100%')
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
