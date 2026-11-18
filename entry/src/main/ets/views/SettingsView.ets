// 设置
// v4.0：纯离线版。没有服务器、没有账号、没有密码 ——
// 所有数据都存在这台手机自己的数据库里（db/Db.ets + db/Repo.ets）。
// 这一页负责三件事：
//   1) 让你看清「我的数据在本机」：各类内容多少条、存在哪
//   2) 备份与恢复：导出 JSON 到文件（v4.30，主）/ 到剪贴板（临时搬运）/ 从文件或剪贴板恢复
//   3) 清空全部数据（自绘确认弹窗）
// v4.20：零权限 —— 系统通知 / 代理提醒整条线已移除，本 App 不申请任何系统权限。
// v5.17：版式从「8 张平级大卡」改成「3 个分组 + 设置行清单」——
//   分组一 · 我的数据：本地数据 / 备份与恢复 / 清空全部数据
//   分组二 · 偏好    ：怎么称呼我 / 外观 / 提醒清单
//   分组三 · 关于    ：隐私与协议 / 关于小记
//   每组一个标题（复用 components/Widgets.ets 的 SecHead）+ 一份行清单；
//   行之间用 1px 分隔线（tk(pal,'line')）断开，不再每行套一张卡（嵌套卡会显碎）；
//   行的可点高度 ≥ 48vp（无障碍）。
//   功能一个没删：导出（文件/剪贴板）、恢复（文件/粘贴）、清空、称呼保存、
//   五套配色、隐私协议跳转、busy 守卫、自绘确认弹窗全部保留。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Store } from '../store/Store';
import { Repo } from '../db/Repo';
import { S, brandGradient, cardShadow, onFill, sheetShadow, tk, tkInk } from '../utils/Theme';
import { R } from '../utils/Responsive';
import { PALETTES, PaletteDef } from '../utils/Palette';
import { D } from '../utils/DateUtil';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { SettingsResp, SettingsPatch, Task, Note, Review, EventItem, Project, HabitView } from '../api/Types';
import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { FileBackup } from '../utils/Backup';
import { TopBar } from '../components/TopBar';
import { SetRow } from '../components/SetRow';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

@Component
export struct SettingsView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  // v5.17：宽屏列数（>1180vp 三列 / >820vp 两列 / 更窄一列）。
  //   R.cols() 读的是 AppStorage，改窗口大小时不会自己触发本页重画 ⇒ 这里挂一个 @StorageLink，
  //   窗口宽度一变（旋转、分屏、拖窗口）本页就会重画，栅格列数跟着变。
  @StorageLink('wb_cols') cols: number = 1;
  @State tick: number = 0;
  @State settings: SettingsResp = { user_name: '', ai_base_url: '', ai_model: '', ai_key_set: false };
  @State tasks: Task[] = [];
  @State notes: Note[] = [];
  @State reviews: Review[] = [];
  @State events: EventItem[] = [];
  @State projects: Project[] = [];
  // v4.4：习惯数原来直接读 Store.I.habits.length —— 那是普通字段不是 @State，
  // 导入/清空之后数字不会自己变，所以改成同步一份到 @State。
  @State habits: HabitView[] = [];
  @State userName: string = '';
  // v5.7：上次「保存」时写进库的称呼。用来判断输入框里的字是不是用户正在新敲的 ——
  //   只有没在改的时候才让 Store 的值回填输入框，否则用户正打字会被 store 通知冲掉。
  private lastSavedName: string = '';
  // v4.25：这几页的「多少条」不能直接写 `${this.tasks.length}`。
  //   ArkUI V1 不会因为「@State 数组换了个新引用」就重画那个只读了 .length 的节点 ——
  //   内存里 this.tasks 已经是空数组了，界面还显示着旧的数字（AGC 审核在 Mate 80 Pro 上
  //   报的「清空数据后设置页没更新」就是这个）。
  //   ⇒ 派生数字先算进 @State（跟 v4.2 任务面板的三列计数同一个套路），界面直接读数字。
  @State nTasks: number = 0;
  @State nEvents: number = 0;
  @State nNotes: number = 0;
  @State nReviews: number = 0;
  @State nProjects: number = 0;
  @State nHabits: number = 0;
  // 版本号从系统读，改了 app.json5 不用再改这里
  @State appVersion: string = 'v1.0.0';
  @State busy: boolean = false;
  @State backupText: string = '';
  // v5.17：备份卡的「粘贴恢复」框默认收起 —— 把原来那张又长又大的卡折进一行小字链接后面。
  @State showPaste: boolean = false;
  private unsub: () => void = () => {};

  private readVersion(): void {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(0);
      this.appVersion = `v${info.versionName} (${info.versionCode})`;
    } catch (e) {
      this.appVersion = 'v1.0.0';
    }
  }

  private syncStore(): void {
    this.settings = Store.I.settings;
    // v5.7：称呼也要跟着 Store 走。
    //   之前只有 aboutToAppear 才把 Store 的称呼灌进输入框，于是「恢复备份」之后
    //   输入框还是空的 —— 看着像没恢复，其实库里已经写回去了；用户再点一次「保存名字」
    //   就把恢复好的称呼又覆盖成空。
    const n: string = this.settings.user_name;
    if (this.userName === this.lastSavedName) {
      this.userName = n;
    }
    this.lastSavedName = n;
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.reviews = Store.I.reviews;
    this.events = Store.I.events;
    this.projects = Store.I.projects;
    this.habits = Store.I.habits;
    this.nTasks = this.tasks.length;
    this.nEvents = this.events.length;
    this.nNotes = this.notes.length;
    this.nReviews = this.reviews.length;
    this.nProjects = this.projects.length;
    this.nHabits = this.habits.length;
  }
  onNavigate: (page: string) => void = () => {};
  // v5.17：二级页返回（Index 传进来的）
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.readVersion();
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
    this.userName = this.settings.user_name;
    this.lastSavedName = this.userName;
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  // ───────────────────────── 本地数据 ─────────────────────────

  /** 把整个本地库导出成一段 JSON 文本（复制到剪贴板，换机时用） */
  private async exportBackup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const text: string = await Repo.exportJson();
      const pb = pasteboard.getSystemPasteboard();
      await pb.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      const kb: number = Math.round(text.length / 1024);
      toast(this.getUIContext(), `已复制 ${kb}KB 备份到剪贴板`);
    } catch (e) {
      toast(this.getUIContext(), '导出失败：' + (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  /**
   * v4.30：导出成文件（主备份方式）。
   * 用系统的文件选择器，用户自己选地方存 —— 文件再大都没问题，
   * 存到网盘目录就顺带跨设备了，也不需要任何系统权限。
   */
  private async exportToFile(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const text: string = await Repo.exportJson();
      const kb: number = Math.round(text.length / 1024);
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uri: string = await FileBackup.save(ctx, text, this.stampName());
      if (uri.length === 0) {
        toast(this.getUIContext(), '已取消导出');
        return;
      }
      toast(this.getUIContext(), `已导出 ${kb}KB 备份文件`);
    } catch (e) {
      toast(this.getUIContext(), '导出失败：' + (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  /**
   * v4.30：从文件恢复。
   * 选一个 .json 备份文件读进来，填进下面那个框，再走原来那套「二次确认 → 覆盖恢复」。
   */
  private async restoreFromFile(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    let text: string = '';
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      text = await FileBackup.pick(ctx);
    } catch (e) {
      this.busy = false;
      toast(this.getUIContext(), '读取失败：' + (e as Error).message);
      return;
    }
    this.busy = false;
    if (text.trim().length === 0) {
      toast(this.getUIContext(), '已取消');
      return;
    }
    this.backupText = text;
    this.askRestore();
  }

  /** 备份文件名：小记备份-20261115-2216.json（本地墙上时间） */
  private stampName(): string {
    const d: Date = new Date();
    const p2 = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    const y: string = `${d.getFullYear()}${p2(d.getMonth() + 1)}${p2(d.getDate())}`;
    const hm: string = `${p2(d.getHours())}${p2(d.getMinutes())}`;
    return `小记备份-${y}-${hm}.json`;
  }

  /**
   * 从备份文本恢复（覆盖式：先清空再写入）。
   * 备份内容由用户长按粘贴进下面的输入框 —— 不用读剪贴板的权限，
   * 也不会碰到系统弹权限框。
   */
  private async restoreFromText(): Promise<void> {
    hilog.debug(0x0000, 'workbench', 'restoreFromText enter busy=%{public}d len=%{public}d', this.busy ? 1 : 0, this.backupText.length);
    if (this.busy) { return; }
    const text: string = this.backupText.trim();
    if (text.length === 0) {
      toast(this.getUIContext(), '先把备份内容粘贴进来');
      return;
    }
    this.busy = true;
    try {
      const r = await Repo.importJson(text);
      await Store.I.loadAll();
      // v5.7：恢复完要把称呼也刷回输入框（备份里带称呼，一起恢复了）
      this.userName = this.settings.user_name;
      this.lastSavedName = this.userName;
      this.backupText = '';
      toast(this.getUIContext(), `已恢复 ${r.count} 条内容`);
    } catch (e) {
      // v4.4：失败文案必须写明「原数据没有动」——之前是「先清库再报错」，会吓人
      toast(this.getUIContext(), (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  /** 恢复是覆盖式的：先弹确认，让人知道「现在这份会被换掉」 */
  private askRestore(): void {
    if (this.busy) { return; }
    if (this.backupText.trim().length === 0) {
      toast(this.getUIContext(), '先把备份内容粘贴进来');
      return;
    }
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '用备份覆盖现在的数据？',
      '这台手机上的任务、日程、记录、项目、复盘和习惯都会被备份里的内容替换掉，替换后找不回来。建议先「存成文件」留一份现在的。',
      '覆盖恢复',
      () => { this.restoreFromText(); });
  }

  /** 清空全部数据（危险操作，必须走自绘确认弹窗） */
  private askClear(): void {
    // v5.14：正在忙（比如正在恢复备份）时不要弹清空框 ——
    //   两个操作叠在一起，用户会以为点错了。
    if (this.busy) { return; }
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '清空全部数据？',
      '这台手机上的任务、日程、记录、项目、复盘、习惯，还有你的称呼，都会被删除，删掉找不回来。建议先复制一份备份。',
      '全部清空',
      () => { this.doClear(); });
  }

  private async doClear(): Promise<void> {
    // v5.14：加 busy 守卫 —— 连点两下「全部清空」会跑两次 clearAll，
    //   第一次还没跑完第二次就开始（而且 Restore 也在跑的话更乱）。
    if (this.busy) { return; }
    this.busy = true;
    try {
      // v5.14：clearAll 现在包在事务里 —— 中途出错会整体回滚，
      //   不会像以前那样留下「清了一半」的库，界面却还说清成功了。
      await Repo.clearAll();
      await Store.I.loadAll();
      // v4.28：称呼也是一起被清掉的，输入框里那个旧名字也要跟着清 ——
      // 之前只刷了 Store，输入框还留着旧值，看着像没清干净，再点保存又会写回去。
      this.userName = '';
      this.lastSavedName = '';
      toast(this.getUIContext(), '已清空');
    } catch (e) {
      toast(this.getUIContext(), '清空失败：' + (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

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

  // v4.20：零权限 —— 系统通知 / 代理提醒整条线已移除，下面不再有提醒相关方法。

  private async saveName(): Promise<void> {
    const body: SettingsPatch = { user_name: this.userName } as SettingsPatch;
    // v4.4：用 saveSettings 的返回值判成败。原来读 Store.I.lastError ——
    // 那个值可能是上一次搜索失败留下的，保存成功也会弹一个旧错误。
    const ok: boolean = await Store.I.saveSettings(body);
    if (ok) {
      this.lastSavedName = this.userName;
    }
    toast(this.getUIContext(), ok ? '存好了' : '没存上，再试一次');
  }

  /** v5.7：切换配色方案（存本地 + 立刻生效） */
  private pickPalette(idx: number): void {
    AppStorage.set<number>('wb_pal', idx);
    this.pal = idx;
    Store.I.setPalette(idx).then((ok: boolean) => {
      if (!ok) {
        toast(this.getUIContext(), '没存上，重启后再试一次');
      }
    });
  }

  // ───────────────────── v5.20：设置页重做（版式全换） ─────────────────────
  //
  //  为什么重做：v5.17 把 8 张平级大卡压成「3 个分组 + 行清单」，但每行里
  //  塞着「标题 + 副标题 + 1~2 个按钮」，一屏 8 个功能挤成一团，看着乱。
  //
  //  现在的样子（照系统设置页）：
  //    组标题（小字灰）→ 一张卡 → 卡里一行一个功能
  //      左：图标块（32vp 圆角底 + 符号）
  //      中：标题 + 一行说明
  //      右：值 / 箭头 / 按钮
  //    真正的操作收进底部抽屉：
  //      「备份与恢复」→ 抽屉里 4 个动作（导出为文件 / 从文件恢复 / 复制备份 / 粘贴恢复）
  //      「外观」→ 抽屉里 5 套配色
  //    主页面因此只剩 8 行，一眼扫得完。
  //
  //  配色没有新造，还是 utils/Palette.ets 里那五套（A 深海青 / B 靛蓝墨 /
  //  C 墨绿米白 / D 陶土暖橙 / E 雾紫冷调，默认 E）。
  //  功能一个没删：导出（文件/剪贴板）、恢复（文件/粘贴）、清空、称呼保存、
  //  换配色、隐私协议跳转、busy 守卫、自绘确认弹窗全部保留。

  /** 分隔线的缩进（卡内左边距 + 图标块 + 间距），让线不顶到图标 */
  private rowIndent: number = 44;
  /** 设置行的最小高度 */
  private rowMinH: number = 56;
  /** 称呼输入框高度 */
  private nameInputH: number = 38;
  /** 粘贴备份内容的输入框高度 */
  private pasteBoxH: number = 84;
  /** v5.20：抽屉开着吗 + 抽屉里放什么（1 = 备份，2 = 配色） */
  @State showSheet: boolean = false;
  @State sheetMode: number = 0;

  private openBackup(): void {
    this.sheetMode = 1;
    this.showSheet = true;
  }

  private openPalette(): void {
    this.sheetMode = 2;
    this.showSheet = true;
  }

  /** v5.20：宽屏？宽屏的抽屉改成居中卡片 */
  private wideMode(): boolean {
    return R.wide();
  }

  // ── 设置行的零件 ──

  /** 组标题：小字灰，缩进一点（系统设置页的样子） */
  @Builder
  groupTitle(text: string, first: boolean) {
    Text(text)
      .fontSize(S.smallSize)
      .fontWeight(FontWeight.Medium)
      .fontColor(tk(this.pal, 'textSub'))
      .letterSpacing(0.8)
      .width('100%')
      .padding({ left: S.spaceSm, top: first ? S.spaceXl : S.space6Xl, bottom: S.spaceLg })
  }

  /** 行之间的细线（缩进到文字起点） */
  @Builder
  rowDivider() {
    Divider().color(tk(this.pal, 'line')).strokeWidth(1).margin({ left: this.rowIndent })
  }

  /** 主色小按钮（品牌渐变底） */
  @Builder
  miniPrimaryBtn(text: string, cb: () => void) {
    Text(text)
      .fontSize(S.labelSize)
      .fontColor(onFill(this.pal))
      .textAlign(TextAlign.Center)
      .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceXl, bottom: S.spaceXl  })
      .borderRadius(S.radiusSm)
      .linearGradient(brandGradient(this.pal))
      .onClick(cb)
  }

  /** 次级小按钮（描边） */
  @Builder
  miniGhostBtn(text: string, cb: () => void) {
    Text(text)
      .fontSize(S.labelSize)
      .fontColor(tkInk(this.pal, 'brandDeep'))
      .textAlign(TextAlign.Center)
      .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceXl, bottom: S.spaceXl  })
      .borderRadius(S.radiusSm)
      .backgroundColor(tk(this.pal, 'card'))
      .border({ width: 1, color: tk(this.pal, 'line') })
      .onClick(cb)
  }

  /** 纯文字按钮（无底色，用在次级入口上） */
  @Builder
  textBtn(text: string, cb: () => void) {
    Text(text)
      .fontSize(S.labelSize)
      .fontColor(tkInk(this.pal, 'brandDeep'))
      .padding({  left: S.spaceSm, right: S.spaceSm, top: S.spaceXs, bottom: S.spaceXs  })
      .onClick(cb)
  }

  /**
   * 本地数据的紧凑数字摘要。
   *
   * ⚠️ 数字必须在 builder 内部直接读 state —— ArkUI V1 里 @Builder 的参数是按值传的，
   *    把算出来的值当参数传进来，state 变了这里不会重画（v4.25 踩过这个坑）。
   */
  @Builder
  localSummary() {
    Text(`${this.nTasks} 任务 · ${this.nEvents} 日程 · ${this.nNotes} 记录 · ${this.nProjects} 项目 · ${this.nReviews} 复盘 · ${this.nHabits} 习惯`)
      .fontSize(S.labelSize)
      .fontColor(tk(this.pal, 'textSub'))
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder pageTop() {
    TopBar({
      backLabel: '返回',
      onBack: () => { this.onBack(); },
      showBell: false,
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  /**
   * v5.17 宽屏两栏：栅格总列数。
   * 网页端 .settings-grid 是两列，首页 .home-grid 是三列 ⇒ 宽屏最多三列（1/2/3），手机一列。
   */
  private gridCols(): number {
    return this.cols >= 1 ? this.cols : 1;
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

  // ───────────────────── 分组一 · 我的数据 ─────────────────────

  /**
   * 「本地数据」这一行单独写 —— 它的副标题（多少条）是活的，
   * 得在 builder 里直接读 state（v4.25 的坑），走不了 SetRow 的字符串参数。
   */
  @Builder
  rowLocalData() {
    Row({  space: S.space2Xl  }) {
      Column() {
        SymbolGlyph(sym('folder'))
          .fontSize(S.iconSize)
          .fontColor([tkInk(this.pal, 'brandDeep')])
      }
      .width(32)
      .height(32)
      .borderRadius(S.radiusSm)
      .backgroundColor(tk(this.pal, 'soft'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .flexShrink(0)

      Column({  space: S.spaceXs  }) {
        Text('本地数据')
          .fontSize(S.cardTitleSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(tk(this.pal, 'text'))
        this.localSummary()
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: this.rowMinH })
    .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceXl, bottom: S.spaceXl  })
  }

  @Builder
  secData() {
    Column() {
      this.groupTitle('我的数据', true)
      Column() {
        this.rowLocalData()
        this.rowDivider()
        SetRow({
          icon: 'doc',
          title: '备份与恢复',
          sub: '导出、恢复、换机带走',
          arrow: true,
          onTap: () => { this.openBackup(); }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(tk(this.pal, 'card'))
      .borderRadius(S.radiusCard)
      .border({ width: 1, color: tk(this.pal, 'cardBorder') })
      .shadow(cardShadow(this.pal))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ───────────────────── 分组二 · 偏好 ─────────────────────

  @Builder
  secPref() {
    Column() {
      this.groupTitle('偏好', false)
      Column() {
        SetRow({
          icon: 'person',
          title: '怎么称呼我',
          sub: '会显示在首页问候语右上角'
        })

        this.rowDivider()

        // 称呼输入框（单独一行：右侧固定宽度会把标题挤没）
        Row({  space: S.spaceLg  }) {
          TextInput({ placeholder: '你的名字', text: this.userName })
            .fontSize(S.smallSize)
            .layoutWeight(1)
            .height(this.nameInputH)
            .placeholderFont({ size: S.smallSize })
            .placeholderColor(tk(this.pal, 'textHint'))
            .fontColor(tk(this.pal, 'text'))
            .caretColor(tk(this.pal, 'brand'))
            .backgroundColor(tk(this.pal, 'card2'))
            .borderRadius(S.radiusBtn)
            .border({ width: 1, color: tk(this.pal, 'line') })
            .padding({  left: S.space2Xl, right: S.space2Xl  })
            .onChange((v: string) => { this.userName = v; })
          this.miniPrimaryBtn('保存', () => { this.saveName(); })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({  left: this.rowIndent, right: S.space2Xl, top: S.spaceXl, bottom: S.spaceXl  })

        this.rowDivider()

        SetRow({
          icon: 'palette',
          title: '外观',
          sub: '五套配色，点一下就换',
          arrow: true,
          trailingKind: 1,
          onTap: () => { this.openPalette(); }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(tk(this.pal, 'card'))
      .borderRadius(S.radiusCard)
      .border({ width: 1, color: tk(this.pal, 'cardBorder') })
      .shadow(cardShadow(this.pal))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ───────────────────── 分组三 · 关于 ─────────────────────

  @Builder
  secAbout() {
    Column() {
      this.groupTitle('关于', false)
      Column() {
        SetRow({
          icon: 'bell',
          title: '提醒清单',
          sub: '在顶部铃铛里看 · 纯本地，不申请权限'
        })

        this.rowDivider()

        SetRow({
          icon: 'checkCircle',
          title: '隐私与协议',
          sub: '不联网 · 不收集个人信息',
          arrow: true,
          onTap: () => { this.onNavigate('policy'); }
        })

        this.rowDivider()

        SetRow({
          icon: 'grid',
          title: '关于小记',
          sub: '本机数据库',
          trailingKind: 2,
          trailingText: this.appVersion
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(tk(this.pal, 'card'))
      .borderRadius(S.radiusCard)
      .border({ width: 1, color: tk(this.pal, 'cardBorder') })
      .shadow(cardShadow(this.pal))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ───────────────────── 分组四 · 危险操作 ─────────────────────

  @Builder
  secDanger() {
    Column() {
      this.groupTitle('危险操作', false)
      Column() {
        SetRow({
          icon: 'trash',
          title: '清空全部数据',
          sub: '不可撤销',
          trailingKind: 2,
          trailingText: '清空',
          trailingDanger: true,
          onTap: () => { this.askClear(); }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(tk(this.pal, 'card'))
      .borderRadius(S.radiusCard)
      .border({ width: 1, color: tk(this.pal, 'cardBorder') })
      .shadow(cardShadow(this.pal))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ───────────────────── 抽屉 · 备份与恢复 ─────────────────────

  @Builder
  backupActions() {
    Column({  space: S.spaceLg  }) {
      SetRow({
        icon: 'folder',
        title: '导出为文件',
        sub: '存成一个 json 文件，自己选地方存',
        arrow: true,
        onTap: () => { this.exportToFile(); }
      })

      SetRow({
        icon: 'undo',
        title: '从文件恢复',
        sub: '选一个备份文件读回来',
        arrow: true,
        onTap: () => { this.restoreFromFile(); }
      })

      // 复制/粘贴点下去就直接做，不给箭头（箭头表示「会跳去另一个地方」）
      SetRow({
        icon: 'doc',
        title: '复制备份',
        sub: '复制到剪贴板，临时搬着用',
        onTap: () => { this.exportBackup(); }
      })

      SetRow({
        icon: 'checkCircle',
        title: '粘贴恢复',
        sub: '把备份内容贴进来',
        onTap: () => { this.showPaste = !this.showPaste; }
      })

      // 粘贴恢复：把备份内容贴进来再恢复（不读剪贴板、不申请任何权限）
      if (this.showPaste) {
        Column({  space: S.spaceLg  }) {
          TextArea({ placeholder: '把备份内容粘贴到这里', text: this.backupText })
            .fontSize(S.labelSize)
            .width('100%')
            .height(this.pasteBoxH)
            .placeholderFont({ size: S.labelSize })
            .placeholderColor(tk(this.pal, 'textHint'))
            .fontColor(tk(this.pal, 'text'))
            .caretColor(tk(this.pal, 'brand'))
            .backgroundColor(tk(this.pal, 'card2'))
            .borderRadius(S.radiusBtn)
            .border({ width: 1, color: tk(this.pal, 'line') })
            .padding({  left: S.space2Xl, right: S.space2Xl, top: S.space2Xl, bottom: S.space2Xl  })
            .onChange((v: string) => { this.backupText = v; })
          Row({  space: S.spaceLg  }) {
            this.textBtn('清空输入框', () => { this.backupText = ''; });
            this.miniGhostBtn('用粘贴内容恢复', () => { this.askRestore(); });
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ───────────────────── 抽屉 · 外观 ─────────────────────

  @Builder
  paletteList() {
    Column({  space: S.spaceSm  }) {
      ForEach(PALETTES, (p: PaletteDef, i: number) => {
        this.paletteRow(p, i);
      }, (p: PaletteDef) => `pal-${p.key}-${this.pal}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 一套配色（一行，点一下就换） */
  @Builder
  paletteRow(p: PaletteDef, i: number) {
    Row({  space: S.space2Xl  }) {
      Row()
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor(p.map['brand'] ?? tk(this.pal, 'brand'))
        .border({ width: this.pal === i ? 2 : 1,
                  color: this.pal === i ? tk(this.pal, 'brandDeep') : tk(this.pal, 'line') })
        .flexShrink(0)
      Column({  space: S.spaceXs  }) {
        Text(p.name)
          .fontSize(S.cardTitleSize).fontWeight(FontWeight.Medium)
          .fontColor(tk(this.pal, 'text'))
        Text(p.desc)
          .fontSize(S.labelSize).fontColor(tk(this.pal, 'textHint'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.pal === i) {
        SymbolGlyph(sym('check'))
          .fontSize(S.midSize).fontColor([tk(this.pal, 'brand')])
          .flexShrink(0)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: this.rowMinH })
    .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceXl, bottom: S.spaceXl  })
    .onClick(() => { this.pickPalette(i); this.showSheet = false; })
  }

  // ───────────────────── 抽屉外壳 ─────────────────────

  @Builder
  sheetContent() {
    if (this.wideMode()) {
      // 宽屏：居中白卡（遮罩由系统的 POPUP 弹窗画）
      Column() {
        this.sheetBody()
      }
      .width('86%')
      .constraintSize({ maxWidth: 460, maxHeight: R.sheetMaxH() })
      .backgroundColor(tk(this.pal, 'card'))
      .borderRadius(S.radiusSheet)
      .shadow(sheetShadow(this.pal))
    } else {
      // 窄屏：贴底抽屉
      Column() {
        this.sheetBody()
      }
      .width('100%')
      .backgroundColor(tk(this.pal, 'card'))
      .borderRadius(S.radiusSheet)
    }
  }

  @Builder
  sheetBody() {
    Column({  space: S.spaceLg  }) {
      Row() {
        Text(this.sheetMode === 1 ? '备份与恢复' : '外观')
          .fontSize(S.sectionSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text'))
        Blank()
        Column() {
          SymbolGlyph(sym('close'))
            .fontSize(S.iconSize).fontColor([tk(this.pal, 'textHint')])
        }
        .width(40).height(40).borderRadius(20)
        .backgroundColor(tk(this.pal, 'soft'))
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.showSheet = false; })
      }
      .width('100%')
      Text(this.sheetMode === 1 ? '导出、恢复、换机带走。' : '五套配色，点一下就换。')
        .fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
        .width('100%')
      if (this.sheetMode === 1) {
        this.backupActions()
      } else {
        this.paletteList()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({  left: S.pagePad, right: S.pagePad, top: S.spaceXl, bottom: S.space2Xl  })
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          Text(`${this.tick}`).fontSize(S.hiddenSize).width(1).height(1).opacity(0)

          this.pageTop()

          // page-head
          Column({  space: S.spaceMd  }) {
            Text('SETTINGS · 偏好设置').fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint')).letterSpacing(1.6)
            Text('偏好')
              .fontSize(S.sectionSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text')).letterSpacing(-0.2)
            Text('这台手机上的小记，全部设置都在这儿。').fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({  top: S.spaceXl, bottom: S.space2Xl  })

          // v5.17 宽屏两栏：分组并排（>1180vp 三列 / >820vp 两列），手机仍是单列。
          if (this.gridCols() >= 2) {
            GridRow({ columns: this.gridCols(), gutter: { x: S.gapLg, y: S.gapLg } }) {
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  this.secData()
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  this.secPref()
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              GridCol({ span: this.spanFor(1) }) {
                Column() {
                  this.secAbout()
                  this.secDanger()
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
          } else {
            this.secData()
            this.secPref()
            this.secAbout()
            this.secDanger()
          }

          Text(`离线版 · 数据存在本机 · ${this.appVersion} · ${D.mdWeek(D.key(new Date()))}`)
            .fontSize(S.tinySize).fontColor(tk(this.pal, 'textPale')).textAlign(TextAlign.Center)
            .width('100%').margin({  top: S.space2Xl, bottom: R.bottomPad()  })
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
    }
    .width('100%')
    .height('100%')
    // v5.20：备份 / 配色两个抽屉共用一个 bindSheet（同一个组件只能挂一个）
    .bindSheet($$this.showSheet, this.sheetContent(), {
      // v5.21：宽屏用系统的「居中弹窗」（CENTER）。
      //   之前用 POPUP + height '100%'，实测面板高度是按内容算的（平板横屏也只有内容那么高），
      //   结果卡片贴在屏幕顶部、垂直方向没居中 —— 平板上看着像一张掉下来的横幅。
      //   CENTER + FIT_CONTENT 才是真正按内容居中。
      height: SheetSize.FIT_CONTENT,
      dragBar: !this.wideMode(),
      showClose: false,
      backgroundColor: Color.Transparent,
      width: '100%',
      preferType: this.wideMode() ? SheetType.CENTER : SheetType.BOTTOM
    })
  }

}
