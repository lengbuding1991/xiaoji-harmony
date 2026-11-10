// 主容器：主界面 + 次级页
// 布局对齐「个人工作台」手机端：底部 4 个主入口 + 右侧「更多」，白底 94%、
// 图标 17px、文字 9px、选中态用主色青绿。
//
// v4.0：完全离线。没有登录门、没有服务器地址；数据全部来自手机本地数据库
// （db/Db.ets + db/Repo.ets）。打开 App 直接进主界面。
import { Store } from '../store/Store';
import { Boot } from '../db/Boot';
import { C, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from '../components/Icon';
import { R, Layout } from '../utils/Responsive';
import { SideRail } from '../components/SideRail';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { Privacy } from '../utils/Privacy';
import { PrivacyDialog } from '../components/PrivacyDialog';
import { PolicyView } from '../views/PolicyView';

import { HomeView } from '../views/HomeView';
import { TasksView } from '../views/TasksView';
import { CalendarView } from '../views/CalendarView';
import { NotesView } from '../views/NotesView';
import { MoreSheet } from '../components/MoreSheet';
import { EdgeHint } from '../components/EdgeHint';
import { QuickNote } from '../components/QuickNote';
import { HabitsView } from '../views/HabitsView';
import { ProjectsView } from '../views/ProjectsView';
import { ReviewView } from '../views/ReviewView';
import { StatsView } from '../views/StatsView';
import { SearchView } from '../views/SearchView';
import { SettingsView } from '../views/SettingsView';
import { AllView } from '../views/AllView';

const DOMAIN = 0x0000;

interface TabMeta {
  icon: string;
  iconOn: string;
  label: string;
  key: string;
}

@Entry
@Component
struct Index {
  @State ready: boolean = false;
  // v4.4：开库失败时的说明（空 = 没问题）。以前是永远卡在「正在打开本地数据…」
  @State bootError: string = '';
  @StorageLink('wb_dragging') dragging: boolean = false;   // 任务拖拽中：藏起右下角悬浮按钮
  @StorageLink('wb_scrolling') scrolling: boolean = false;  // 页面滚动中：藏起悬浮按钮（别压住图表气泡）
  @StorageLink('wb_fab_hide') fabHide: boolean = false;   // 图表末点气泡正好在悬浮按钮下面时，让按钮让开
  @State activeTab: number = 0;
  @State subPage: string = '';
  @State showMore: boolean = false;
  @State showQuick: boolean = false;
  // v4.4：记录灵感的编辑器是居中弹窗，打开时把底部导航藏掉，
  // 不然弹窗下面还露着一条导航栏，看起来像没盖住。
  @State hideTabBar: boolean = false;
  // 通知点进来 → EntryAbility 写 AppStorage → @Watch 收到 → 切到目标页。
  // wb_dl_nonce 保证「同一个页面连点两次通知」也能触发（值变了才回调）。
  @StorageLink('wb_open_page') @Watch('onDeepLink') openPage: string = '';
  @StorageLink('wb_dl_nonce') @Watch('onDeepLink') dlNonce: number = 0;
  // 系统导航条高度（vp）：EntryAbility 量好写进来，底部导航用它下压贴底
  @StorageLink('wb_bottom_inset') bottomInset: number = 0;
  // v4.6：宽屏（平板 / 折叠屏展开）布局档位。0 手机、1 小平板、2 平板
  @StorageLink('wb_layout') layoutMode: number = 0;
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  // v4.6：横屏时系统导航条可能在左右两侧，悬浮按钮要躲开
  @StorageLink('wb_side_inset') sideInset: number = 0;
  // v4.7：隐私门。同意《用户协议》《隐私政策》之前不进入 App（应用市场审核要求）
  @StorageLink('wb_privacy_ok') privacyOk: boolean = false;
  @StorageLink('wb_privacy_ready') privacyReady: boolean = false;

  private readonly tabs: TabMeta[] = [
    { icon: 'home', iconOn: 'homeFill', label: '成长总览', key: 'home' } as TabMeta,
    { icon: 'tasks', iconOn: 'tasksFill', label: '任务面板', key: 'tasks' } as TabMeta,
    { icon: 'calendar', iconOn: 'calendarFill', label: '日历安排', key: 'calendar' } as TabMeta,
    { icon: 'note', iconOn: 'noteFill', label: '记录灵感', key: 'notes' } as TabMeta
  ];

  aboutToAppear(): void {
    // v4.4：记录灵感的编辑器改成居中弹窗后，键盘会把弹窗下半截盖住。
    // 把页面改成「键盘弹出时整体缩高」（默认是 OFFSET = 整页上移，
    // 居中弹窗会被推到屏幕外），弹窗就始终留在可见区域里。
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (e) {
      hilog.error(DOMAIN, 'workbench', 'setKeyboardAvoidMode failed: %{public}s', JSON.stringify(e));
    }
    this.boot();
  }

  onPageShow(): void {
    // 冷启动时 UI 可能先于 @StorageLink 建立，补读一次
    const p: string | undefined = AppStorage.get<string>('wb_open_page');
    if (p && this.ready) { this.applyDeepLink(p); }
  }

  private onDeepLink(): void {
    if (this.ready) { this.applyDeepLink(this.openPage); }
  }

  private applyDeepLink(page: string): void {
    if (page.length === 0) { return; }
    this.go(page);
    // 消费掉，避免下次进前台又跳一遍；nonce 保留以便下次同页通知仍能触发
    AppStorage.setOrCreate<string>('wb_open_page', '');
  }

  /** v4.0：开 App 就是这里 —— 读本地库，不需要登录、不需要服务器 */
  private async boot(): Promise<void> {
    // 等本地库闸门：库还没开好就 loadAll 会读到空库（表现是「打开全是 0」）
    await Boot.when();
    // v4.4：开库失败要说人话 + 给重试，不能永远转圈
    const err: string = Boot.error();
    if (err.length > 0) {
      this.bootError = err;
      return;
    }
    try {
      await Store.I.loadAll();
      await Store.I.restoreTheme();
    } catch (e) {
      this.bootError = (e as Error).message ?? '读取本地数据失败';
      return;
    }
    this.ready = true;
    // 冷启动若是深链进来的，UI 就绪后补跳一次
    const p: string | undefined = AppStorage.get<string>('wb_open_page');
    if (p) { this.applyDeepLink(p); }
  }

  /** 用户点了「同意并开始使用」：记下来，放开 App */
  private async acceptPrivacy(): Promise<void> {
    await Privacy.accept();
    this.privacyOk = true;
  }

  /** 用户点了「不同意」：退出 App（应用市场要求给不同意的人一条出路） */
  private exitApp(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (e) {
      hilog.error(DOMAIN, 'workbench', 'terminateSelf failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 开库失败后重试 */
  private retryBoot(): void {
    this.bootError = '';
    Boot.retry();
    this.boot();
  }

  /**
   * 系统返回键（v4.4 补上，之前全项目没有，系统返回直接退 App）：
   * 快速记一笔 → 更多弹层 → 二级页回主界面 → 都没有了才退出 App。
   */
  onBackPress(): boolean {
    // v4.4：最上面是记录灵感的编辑器（居中弹窗）时，返回键先关弹窗
    if (AppStorage.get<boolean>('wb_note_editor_open') === true) {
      AppStorage.set<boolean>('wb_note_editor_open', false);
      this.hideTabBar = false;
      return true;
    }
    if (this.showQuick) { this.showQuick = false; return true; }
    if (this.showMore) { this.showMore = false; return true; }
    if (this.subPage.length > 0) { this.subPage = ''; return true; }
    return false;
  }

  /** v4.6：现在是宽屏吗（宽屏用左侧导航，不用底部导航） */
  private wideMode(): boolean {
    return this.layoutMode >= Layout.Medium;
  }

  /** v4.6：左侧导航要高亮当前页 */
  private currentKey(): string {
    if (this.subPage.length > 0) { return this.subPage; }
    if (this.activeTab === 1) { return 'tasks'; }
    if (this.activeTab === 2) { return 'calendar'; }
    if (this.activeTab === 3) { return 'notes'; }
    return 'home';
  }

  /** v4.6：Area 里的长度可能是百分比字符串，这里只取数字 */
  private numOf(v: Length | undefined): number {
    if (typeof v === 'number') { return v; }
    return 0;
  }

  private go(page: string): void {
    if (page === 'home') { this.subPage = ''; this.activeTab = 0; return; }
    if (page === 'tasks') { this.subPage = ''; this.activeTab = 1; return; }
    if (page === 'calendar') { this.subPage = ''; this.activeTab = 2; return; }
    if (page === 'notes') { this.subPage = ''; this.activeTab = 3; return; }
    this.subPage = page;
  }

  /** 「更多」里任意一项被选中时，也点亮更多按钮 */
  private inMore(): boolean {
    return this.subPage.length > 0;
  }

  // ── 底部导航 ──
  @Builder navItem(t: TabMeta, idx: number) {
    Column({ space: 3 }) {
      SymbolGlyph(sym(this.activeTab === idx && this.subPage.length === 0 ? t.iconOn : t.icon))
        .fontSize(17)
        .fontColor([this.activeTab === idx && this.subPage.length === 0 ? tkInk(this.dark, 'brand') : tc(this.dark, '#9BAFC0', 1)])
      Text(t.label)
        .fontSize(9)
        .fontColor(this.activeTab === idx && this.subPage.length === 0 ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#9BAFC0', 1))
        .fontWeight(this.activeTab === idx && this.subPage.length === 0 ? FontWeight.Medium : FontWeight.Normal)
    }
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.subPage = '';
      this.activeTab = idx;
    })
  }

  @Builder moreBtn() {
    Column({ space: 3 }) {
      SymbolGlyph(sym(this.inMore() ? 'moreFill' : 'more'))
        .fontSize(17)
        .fontColor([this.inMore() ? tkInk(this.dark, 'brand') : tc(this.dark, '#9BAFC0', 1)])
      Text('更多')
        .fontSize(9)
        .fontColor(this.inMore() ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#9BAFC0', 1))
        .fontWeight(this.inMore() ? FontWeight.Medium : FontWeight.Normal)
    }
    .width(58)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.inMore() ? tk(this.dark, 'brandSoft') : '#00000000')
    .onClick(() => {
      this.showMore = true;
    })
  }

  @Builder bottomBar() {
    Row() {
      ForEach(this.tabs, (t: TabMeta, i: number) => {
        this.navItem(t, i)
      }, (t: TabMeta) => `tab-${t.key}`)
      this.moreBtn()
    }
    .width('100%')
    .height(S.tabBarH + this.bottomInset)
    .padding({ left: 6, right: 6, bottom: this.bottomInset })
    .backgroundColor(this.dark ? 'rgba(20,29,40,0.94)' : 'rgba(255,255,255,0.94)')
    // 网页端是 rgba(255,255,255,.94) + backdrop-filter: blur(10px)；只做半透明白会让下面的
    // 文字透上来变成「重影」，所以这里补一层背景模糊，对齐网页端的观感。
    .backdropBlur(16)
    .border({ width: { top: 1 }, color: tk(this.dark, 'line') })
    // 伸到系统导航条那一条：布局安全区忽略底部，白底才真正贴到屏幕最下沿
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  // ── 右下角悬浮记录按钮（对齐 globals.css .capture-fab：白底圆 42、bottom 76、right 16）──
  @Builder captureFab() {
    Row() {
      SymbolGlyph(sym('pen')).fontSize(16).fontColor([tkInk(this.dark, 'brandDeep')])
    }
    .width(42)
    .height(42)
    .borderRadius(21)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#DCE9F3', 2), 2) })
    .shadow({ radius: 30, color: 'rgba(37,84,133,0.14)', offsetX: 0, offsetY: 12 })
    .onClick(() => { this.showQuick = true; })
  }

  // ── 背景光斑（对齐 globals.css .blobs）──
  // 工作台刻意不用 filter:blur(72px)，改用 radial-gradient 拿到同样的柔光、零滤镜开销。
  // 三个圆：b1 #BFE9F5 右上、b2 #D8EAFB 左下、b3 #E4F7EF 左中。
  @Builder blobs() {
    Stack() {
      Row()
        .width(340).height(340).borderRadius(170)
        .radialGradient({
          center: [170, 170],
          radius: 170,
          colors: [[this.dark ? 'rgba(191,233,245,0.14)' : 'rgba(191,233,245,1)', 0], [this.dark ? 'rgba(191,233,245,0)' : 'rgba(191,233,245,0)', 0.68]]
        })
        .offset({ x: 96, y: -150 })
      Row()
        .width(300).height(300).borderRadius(150)
        .radialGradient({
          center: [150, 150],
          radius: 150,
          colors: [[this.dark ? 'rgba(216,234,251,0.13)' : 'rgba(216,234,251,1)', 0], [this.dark ? 'rgba(216,234,251,0)' : 'rgba(216,234,251,0)', 0.68]]
        })
        .offset({ x: -110, y: 240 })
      Row()
        .width(260).height(260).borderRadius(130)
        .radialGradient({
          center: [130, 130],
          radius: 130,
          colors: [[this.dark ? 'rgba(228,247,239,0.12)' : 'rgba(228,247,239,1)', 0], [this.dark ? 'rgba(228,247,239,0)' : 'rgba(228,247,239,0)', 0.68]]
        })
        .offset({ x: -190, y: 20 })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  // ── 内容区 ──
  @Builder currentTab() {
    if (this.activeTab === 1) {
      TasksView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.activeTab === 2) {
      CalendarView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.activeTab === 3) {
      NotesView({
        onNavigate: (p: string) => { this.go(p); },
        onOverlay: (open: boolean) => { this.hideTabBar = open; }
      })
    } else {
      HomeView({ onNavigate: (p: string) => { this.go(p); } })
    }
  }

  @Builder subContent() {
    if (this.subPage === 'all') {
      AllView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.subPage === 'habits') {
      HabitsView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.subPage === 'projects') {
      ProjectsView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.subPage === 'review') {
      ReviewView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.subPage === 'stats') {
      StatsView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.subPage === 'search') {
      SearchView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.subPage === 'settings') {
      SettingsView({ onNavigate: (p: string) => { this.go(p); } })
    } else if (this.subPage === 'policy') {
      PolicyView({ onNavigate: (p: string) => { this.go(p); } })
    } else {
      // v4.7：MoreView / AiView 是进不去的死页面，已连代码一起删掉
      Column() { Blank() }
        .width('100%')
        .height('100%')
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景光斑在最底层（不拦截点击）
      this.blobs()

      // v4.6：宽屏（平板 / 折叠屏展开）＝ 左边导航栏 + 右边内容区（照网页端）
      Row() {
        if (this.wideMode()) {
          SideRail({
            active: this.currentKey(),
            onNavigate: (k: string) => { this.go(k); }
          })
        }
        Column() {
        if (!this.ready && this.bootError.length > 0) {
          // v4.4：开库失败 —— 说清楚为什么，并给一个重试按钮
          Column() {
            Blank()
            Row() {
              SymbolGlyph(sym('close')).fontSize(20).fontColor([onFill(this.dark)])
            }
            .width(44).height(44).borderRadius(13)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(tc(this.dark, '#E89079', 0))
            Text('本地数据打不开')
              .fontSize(15).fontColor(tk(this.dark, 'text')).margin({ top: 14 })
            Text(this.bootError)
              .fontSize(10.5).fontColor(tk(this.dark, 'textSub')).margin({ top: 6 })
              .textAlign(TextAlign.Center).maxLines(3)
            Text('点下面重试；还是不行就完全退出 App 再打开一次。')
              .fontSize(10.5).fontColor(tk(this.dark, 'textHint')).margin({ top: 6 })
            Text('重试')
              .fontSize(12).fontColor(onFill(this.dark))
              .padding({ left: 22, right: 22, top: 9, bottom: 9 })
              .borderRadius(11)
              .backgroundColor(tk(this.dark, 'brand'))
              .margin({ top: 16 })
              .onClick(() => { this.retryBoot(); })
            Blank()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (!this.ready) {
          // 本地库读数据的几百毫秒：给一个安静的等待态（不闪登录页）
          Column() {
            Blank()
            Row() {
              SymbolGlyph(sym('tasksFill')).fontSize(20).fontColor([onFill(this.dark)])
            }
            .width(44).height(44).borderRadius(13)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
            Text('正在打开本地数据…')
              .fontSize(11).fontColor(tk(this.dark, 'textSub'))
              .margin({ top: 12 })
            Blank()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (!this.privacyOk) {
          // v4.7：隐私门 —— 没同意之前不渲染任何业务内容，只留一张安静的启动页
          Column() {
            Blank()
            Row() {
              SymbolGlyph(sym('tasksFill')).fontSize(22).fontColor([onFill(this.dark)])
            }
            .width(54).height(54).borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
            Text('小记')
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).margin({ top: 14 })
            Text('安排好行动，让生活慢慢生长。')
              .fontSize(10.5).fontColor(tk(this.dark, 'textSub')).margin({ top: 6 })
            Blank()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(tk(this.dark, 'bg'))
        } else if (this.subPage.length > 0) {
          Column() {
            Column() {
              this.subContent()
            }
            .width('100%')
            .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        } else {
          Column() {
            this.currentTab()
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
        }
        .layoutWeight(1)
        .height('100%')
        .padding({ left: this.wideMode() ? 16 : 0, right: this.wideMode() ? 16 : 0 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Top)

      // 右下角悬浮记录按钮（弹窗打开时隐藏，对齐 body:has(.modal) .capture-fab{display:none}）
      if (this.ready && this.privacyOk && !this.showQuick && !this.showMore && this.subPage.length === 0 && !this.dragging && !this.scrolling && !this.fabHide && !this.hideTabBar) {
        Column() {
          this.captureFab()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({ right: 16 + this.sideInset, bottom: this.wideMode() ? (16 + this.bottomInset) : 68 })
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(60)
      }

      // 底部导航（只有窄屏才有；宽屏用左侧导航栏）
      if (this.ready && this.privacyOk && !this.hideTabBar && !this.wideMode()) {
        this.bottomBar()
      }

      // 「更多」弹层（覆盖在底部导航之上）
      if (this.showMore && this.ready) {
        MoreSheet({
          activeKey: this.subPage,
          onNavigate: (k: string) => {
            this.showMore = false;
            this.go(k);
          },
          onClose: () => {
            this.showMore = false;
          }
        })
      }
      // 快速记录浮层（对齐 .qc-overlay：居中卡片，非底部抽屉）
      if (this.showQuick && this.ready) {
        Stack({ alignContent: Alignment.Center }) {
          // 点击遮罩空白处关闭
          Column()
            .width('100%').height('100%')
            .onClick(() => { this.showQuick = false; })
          Column() {
            QuickNote({ onDone: () => { this.showQuick = false; } })
          }
          .width('100%')
          .constraintSize({ maxWidth: 540 })
          .padding({ left: 20, right: 20 })
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(23,52,80,0.18)')
        .zIndex(95)
      }

      // v4.7：隐私门 —— 同意之前只显示隐私弹窗；
      // 点《用户协议》《隐私政策》时，协议页盖在弹窗上面（zIndex 更高）。
      if (this.privacyReady && !this.privacyOk) {
        PrivacyDialog({
          visible: true,
          onAgree: () => { this.acceptPrivacy(); },
          onDisagree: () => { this.exitApp(); },
          onViewPolicy: () => { this.go('policy'); }
        })
          .width('100%')
          .height('100%')
          .zIndex(90)
      }
      if (this.privacyReady && !this.privacyOk && this.subPage === 'policy') {
        PolicyView({ onNavigate: (p: string) => { this.go(p); } })
          .width('100%')
          .height('100%')
          .zIndex(96)
      }

      // v4.24：边界提示胶囊（滑出边界时弹一下「已经到顶了 / 已经到底了」）
      // 放在根 Stack 的最后一层 = 最上面；自己不拦截触摸。
      // 注意：.hitTestBehavior 必须写在**使用处**（自定义组件的节点），写在组件内部只作用到它自己的根节点。
      EdgeHint({})
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(tk(this.dark, 'bg'))
    // v4.6：量窗口宽度 → 定布局档位（折叠屏展开、平板横竖屏都会触发）
    .onAreaChange((oldA: Area, newA: Area) => {
      R.update(this.numOf(newA.width));
    })
  }
}
