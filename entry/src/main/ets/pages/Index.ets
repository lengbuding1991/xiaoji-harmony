// 主容器：主界面 + 次级页
// 布局对齐「个人工作台」手机端：底部 4 个主入口 + 右侧「更多」，白底 94%、
// 图标 17px、文字 9px、选中态用主色青绿。
//
// v4.0：完全离线。没有登录门、没有服务器地址；数据全部来自手机本地数据库
// （db/Db.ets + db/Repo.ets）。打开 App 直接进主界面。
import { Store } from '../store/Store';
import { Boot } from '../db/Boot';
import { blobColors, brandGradient, cardShadow, glassEffect, onFill, rgbaOf, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from '../components/Icon';
import { R, Layout } from '../utils/Responsive';
import { SideRail } from '../components/SideRail';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
import { SearchView } from '../views/SearchView';
import { SettingsView } from '../views/SettingsView';
import { AllView } from '../views/AllView';
import { EditorBus } from '../utils/EditorBus';

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
  // v5.0：首页滚动偏移，背景光斑做 0.12 倍视差
  @StorageLink('wb_scroll_y') scrollY: number = 0;
  @StorageLink('wb_fab_hide') fabHide: boolean = false;   // 图表末点气泡正好在悬浮按钮下面时，让按钮让开
  @State activeTab: number = 0;
  @State subPage: string = '';
  @State showMore: boolean = false;
  @State showQuick: boolean = false;
  // v4.4：随手记的编辑器是居中弹窗，打开时把底部导航藏掉，
  // 不然弹窗下面还露着一条导航栏，看起来像没盖住。
  @State hideTabBar: boolean = false;
  // v5.0：切页时内容轻微淡入 + 上浮（保守档 200ms）
  @State contentFade: number = 1;
  @State contentShift: number = 0;
  // 通知点进来 → EntryAbility 写 AppStorage → @Watch 收到 → 切到目标页。
  // wb_dl_nonce 保证「同一个页面连点两次通知」也能触发（值变了才回调）。
  @StorageLink('wb_open_page') @Watch('onDeepLink') openPage: string = '';
  @StorageLink('wb_dl_nonce') @Watch('onDeepLink') dlNonce: number = 0;
  // 系统导航条高度（vp）：EntryAbility 量好写进来，底部导航用它下压贴底
  @StorageLink('wb_bottom_inset') bottomInset: number = 0;
  // v4.6：宽屏（平板 / 折叠屏展开）布局档位。0 手机、1 小平板、2 平板
  @StorageLink('wb_layout') layoutMode: number = 0;
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  // v4.6：横屏时系统导航条可能在左右两侧，悬浮按钮要躲开
  @StorageLink('wb_side_inset') sideInset: number = 0;
  // v4.7：隐私门。同意《用户协议》《隐私政策》之前不进入 App（应用市场审核要求）

  private readonly tabs: TabMeta[] = [
    { icon: 'home', iconOn: 'homeFill', label: '成长总览', key: 'home' } as TabMeta,
    { icon: 'tasks', iconOn: 'tasksFill', label: '任务面板', key: 'tasks' } as TabMeta,
    { icon: 'calendar', iconOn: 'calendarFill', label: '日历安排', key: 'calendar' } as TabMeta,
    { icon: 'note', iconOn: 'noteFill', label: '随手记', key: 'notes' } as TabMeta
  ];

  aboutToAppear(): void {
    // v4.4：随手记的编辑器改成居中弹窗后，键盘会把弹窗下半截盖住。
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
      await Store.I.restorePalette();
    } catch (e) {
      this.bootError = (e as Error).message ?? '读取本地数据失败';
      return;
    }
    this.ready = true;
    // 冷启动若是深链进来的，UI 就绪后补跳一次
    const p: string | undefined = AppStorage.get<string>('wb_open_page');
    if (p) { this.applyDeepLink(p); }
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
    // v4.4：最上面是随手记的编辑器（居中弹窗）时，返回键先关弹窗
    //
    // v5.14：原来这里直接把 wb_note_editor_open 置成 false —— 状态是单向的，
    //   随手记组件那边只看到「窗口要关了」，**刚写的内容一个字都没落盘**，
    //   而且**关窗和落盘也没有顺序保证**（原来是「发起保存 → 立刻关窗」）。
    //   现在改成请随手记自己走 closeEditor()：先落盘，落盘失败就不关、提示「没存上，内容还在，再试一次」。
    //   注意这里**不要**自己动 hideTabBar —— 关不关由随手记说了算（onOverlay 会告诉我们）。
    if (AppStorage.get<boolean>('wb_note_editor_open') === true) {
      EditorBus.requestClose();
      return true;
    }
    if (this.showQuick) { this.showQuick = false; return true; }
    if (this.showMore) { this.showMore = false; return true; }
    if (this.subPage.length > 0) { this.goBack(); return true; }
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

  // v5.17：二级页返回栈（进二级页时记住上一页，返回时能原路回去）
  @State subStack: string[] = [];

  private goBack(): void {
    const st: string[] = this.subStack;
    if (st.length > 0) {
      const prev: string = st[st.length - 1];
      this.subStack = st.slice(0, st.length - 1);
      this.subPage = prev;
      return;
    }
    this.subPage = '';
  }

  private go(page: string): void {
    // v5.0：切页时把背景光斑的视差归零（不然切到别的页背景还停在偏移位置）
    AppStorage.setOrCreate<number>('wb_scroll_y', 0);
    // v5.16：滚动中切页的话 onScrollStop 不会回调 ⇒ 悬浮按钮会一直藏著，这里复位
    AppStorage.setOrCreate<boolean>('wb_scrolling', false);
    if (page === 'home') { this.subPage = ''; this.activeTab = 0; this.animateContentIn(); return; }
    if (page === 'tasks') { this.subPage = ''; this.activeTab = 1; this.animateContentIn(); return; }
    if (page === 'calendar') { this.subPage = ''; this.activeTab = 2; this.animateContentIn(); return; }
    if (page === 'notes') { this.subPage = ''; this.activeTab = 3; this.animateContentIn(); return; }
    // v5.17：进二级页时把当前页压栈，返回时原路回去
    if (this.subPage.length > 0 && this.subPage !== page) {
      this.subStack = this.subStack.concat([this.subPage]);
    }
    this.subPage = page;
  }

  // v5.0：内容区淡入 + 轻微上浮。
  // 先把透明度压到 0（瞬时），再用 animateTo 拉回 1 —— 这是 ArkUI 里做「入场淡入」的标准写法。
  private animateContentIn(): void {
    this.contentFade = 0;
    this.contentShift = 8;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.contentFade = 1;
      this.contentShift = 0;
    });
  }

  /** 「更多」里任意一项被选中时，也点亮更多按钮 */
  private inMore(): boolean {
    return this.subPage.length > 0;
  }

  // ── 底部导航 ──
  @Builder navItem(t: TabMeta, idx: number) {
    Column({  space: S.spaceSm  }) {
      SymbolGlyph(sym(this.activeTab === idx && this.subPage.length === 0 ? t.iconOn : t.icon))
        .fontSize(S.sectionSize)
        .fontColor([this.activeTab === idx && this.subPage.length === 0 ? tkInk(this.pal, 'brand') : tc(this.pal, '#9BAFC0', 1)])
      Text(t.label)
        .fontSize(S.tinySize)
        .fontColor(this.activeTab === idx && this.subPage.length === 0 ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#9BAFC0', 1))
        .fontWeight(this.activeTab === idx && this.subPage.length === 0 ? FontWeight.Medium : FontWeight.Normal)
    }
    .layoutWeight(1)
    .padding({  top: S.spaceMd, bottom: S.spaceMd  })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      // v5.0：先记下「是不是真的换了页」，再改状态（改了再比就永远相等了）
      const changed: boolean = this.activeTab !== idx || this.subPage.length > 0;
      this.subPage = '';
      this.activeTab = idx;
      if (changed) {
        this.animateContentIn();
      }
    })
    // v5.0：按压回弹
    .stateStyles({ pressed: { .scale({ x: 0.9, y: 0.9 }) } })
    .animation({ duration: 140, curve: Curve.EaseOut })
  }

  @Builder moreBtn() {
    Column({  space: S.spaceSm  }) {
      SymbolGlyph(sym(this.inMore() ? 'moreFill' : 'more'))
        .fontSize(S.sectionSize)
        .fontColor([this.inMore() ? tkInk(this.pal, 'brand') : tc(this.pal, '#9BAFC0', 1)])
      Text('更多')
        .fontSize(S.tinySize)
        .fontColor(this.inMore() ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#9BAFC0', 1))
        .fontWeight(this.inMore() ? FontWeight.Medium : FontWeight.Normal)
    }
    .width(58)
    .padding({  top: S.spaceMd, bottom: S.spaceMd  })
    .borderRadius(S.radiusBtn)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.inMore() ? tk(this.pal, 'brandSoft') : '#00000000')
    .onClick(() => {
      this.showMore = true;
    })
    // v5.0：按压回弹
    .stateStyles({ pressed: { .scale({ x: 0.9, y: 0.9 }) } })
    .animation({ duration: 140, curve: Curve.EaseOut })
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
    .padding({  left: S.spaceMd, right: S.spaceMd, bottom: this.bottomInset  })
    .backgroundColor('rgba(255,255,255,0.94)')
    // 网页端是 rgba(255,255,255,.94) + backdrop-filter: blur(10px)；只做半透明白会让下面的
    // 文字透上来变成「重影」，所以这里补一层背景模糊，对齐网页端的观感。
    // v5.0：升级成真水晶 —— backgroundEffect 除了模糊，还会把背景的饱和度提上去、
    // 亮度微调，比单纯 backdropBlur 更像磨砂玻璃。
    .backgroundEffect(glassEffect(24))
    .border({ width: { top: 1 }, color: tk(this.pal, 'line') })
    // 伸到系统导航条那一条：布局安全区忽略底部，白底才真正贴到屏幕最下沿
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  // ── 右下角悬浮记录按钮（对齐 globals.css .capture-fab：白底圆 42、bottom 76、right 16）──
  @Builder captureFab() {
    Row() {
      SymbolGlyph(sym('pen')).fontSize(S.iconSize).fontColor([tkInk(this.pal, 'brandDeep')])
    }
    .width(42)
    .height(42)
    .borderRadius(S.radiusCard)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(tc(this.pal, '#FFFFFF', 0))
    .border({ width: 1, color: tc(this.pal, tc(this.pal, '#DCE9F3', 2), 2) })
    .shadow(cardShadow(this.pal))
    // v5.0：悬浮按钮也做成玻璃珠
    .backgroundEffect(glassEffect(20))
    .onClick(() => { this.showQuick = true; })
    // v5.0：按压回弹
    .stateStyles({ pressed: { .scale({ x: 0.9, y: 0.9 }) } })
    .animation({ duration: 140, curve: Curve.EaseOut })
  }

  // ── 背景光斑（对齐 globals.css .blobs）──
  // 工作台刻意不用 filter:blur(72px)，改用 radial-gradient 拿到同样的柔光、零滤镜开销。
  // 三个圆：b1 #BFE9F5 右上、b2 #D8EAFB 左下、b3 #E4F7EF 左中。
  // ── 背景光斑（v5.0 改成「大面积彩色光斑」）──
  // 工作台刻意不用 filter:blur(72px)，改用 radial-gradient 拿到同样的柔光、零滤镜开销。
  // v5.0：原来只有 3 个 260~340vp 的小光斑挤在角落；现在换成 5 个 420~620vp 的大色斑铺满整屏，
  // 卡片浮在上面才有「磨砂玻璃压在彩色背景上」的感觉（纯色底上做模糊是看不出效果的）。
  // 视差：滚动时整层光斑跟着往反方向挪一点点（0.12 倍），制造纵深。
  @Builder blobs() {
    Stack() {
      Row()
        .width(520).height(520).borderRadius(260)
        .radialGradient({
          center: [260, 260],
          radius: 260,
          colors: [[rgbaOf(blobColors(this.pal)[0], 1), 0], [rgbaOf(blobColors(this.pal)[0], 0), 0.7]]
        })
        .offset({ x: 140, y: -300 })
      Row()
        .width(480).height(480).borderRadius(240)
        .radialGradient({
          center: [240, 240],
          radius: 240,
          colors: [[rgbaOf(blobColors(this.pal)[1], 1), 0], [rgbaOf(blobColors(this.pal)[1], 0), 0.7]]
        })
        .offset({ x: -250, y: -220 })
      Row()
        .width(540).height(540).borderRadius(270)
        .radialGradient({
          center: [270, 270],
          radius: 270,
          colors: [[rgbaOf(blobColors(this.pal)[2], 1), 0], [rgbaOf(blobColors(this.pal)[2], 0), 0.7]]
        })
        .offset({ x: 210, y: 60 })
      Row()
        .width(560).height(560).borderRadius(280)
        .radialGradient({
          center: [280, 280],
          radius: 280,
          colors: [[rgbaOf(blobColors(this.pal)[3], 1), 0], [rgbaOf(blobColors(this.pal)[3], 0), 0.7]]
        })
        .offset({ x: -280, y: 220 })
      Row()
        .width(500).height(500).borderRadius(250)
        .radialGradient({
          center: [250, 250],
          radius: 250,
          colors: [[rgbaOf(blobColors(this.pal)[4], 1), 0], [rgbaOf(blobColors(this.pal)[4], 0), 0.7]]
        })
        .offset({ x: 60, y: 330 })
    }
    .width('100%')
    .height('100%')
    // v5.0：滚动视差（首页滚动时上报偏移，这一层往反方向挪 0.12 倍）
    .translate({ y: -this.scrollY * 0.12 })
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
      AllView({ onNavigate: (p: string) => { this.go(p); }, onBack: () => { this.goBack(); } })
    } else if (this.subPage === 'habits') {
      HabitsView({ onNavigate: (p: string) => { this.go(p); }, onBack: () => { this.goBack(); } })
    } else if (this.subPage === 'projects') {
      ProjectsView({ onNavigate: (p: string) => { this.go(p); }, onBack: () => { this.goBack(); } })
    } else if (this.subPage === 'review') {
      ReviewView({ onNavigate: (p: string) => { this.go(p); }, onBack: () => { this.goBack(); } })
    } else if (this.subPage === 'search') {
      SearchView({ onNavigate: (p: string) => { this.go(p); }, onBack: () => { this.goBack(); } })
    } else if (this.subPage === 'settings') {
      SettingsView({ onNavigate: (p: string) => { this.go(p); }, onBack: () => { this.goBack(); } })
    } else if (this.subPage === 'policy') {
      PolicyView({ onNavigate: (p: string) => { this.go(p); }, onBack: () => { this.goBack(); } })
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
              SymbolGlyph(sym('close')).fontSize(S.heroIconSize).fontColor([onFill(this.pal)])
            }
            .width(44).height(44).borderRadius(S.radiusInner)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(tc(this.pal, '#A83440', 0))
            Text('本地数据打不开')
              .fontSize(S.headSize).fontColor(tk(this.pal, 'text')).margin({  top: S.space3Xl  })
            Text(this.bootError)
              .fontSize(S.subSize).fontColor(tk(this.pal, 'textSub')).margin({  top: S.spaceMd  })
              .textAlign(TextAlign.Center).maxLines(3)
            Text('点下面重试；还是不行就完全退出 App 再打开一次。')
              .fontSize(S.subSize).fontColor(tk(this.pal, 'textHint')).margin({  top: S.spaceMd  })
            Text('重试')
              .fontSize(S.smallSize).fontColor(onFill(this.pal))
              .padding({  left: 22, right: 22, top: S.spaceXl, bottom: S.spaceXl  })
              .borderRadius(S.radiusBtn)
              .backgroundColor(tk(this.pal, 'brand'))
              .margin({  top: S.space4Xl  })
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
              SymbolGlyph(sym('tasksFill')).fontSize(S.heroIconSize).fontColor([onFill(this.pal)])
            }
            .width(44).height(44).borderRadius(S.radiusInner)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .linearGradient(brandGradient(this.pal))
            Text('正在打开本地数据…')
              .fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
              .margin({  top: S.space2Xl  })
            Blank()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
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
          // v5.0：切页淡入 + 上浮
          .opacity(this.contentFade)
          .translate({ y: this.contentShift })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
        }
        .layoutWeight(1)
        .height('100%')
        .padding({  left: this.wideMode() ? 16 : 0, right: this.wideMode() ? 16 : 0  })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Top)

      // 右下角悬浮记录按钮（弹窗打开时隐藏，对齐 body:has(.modal) .capture-fab{display:none}）
      // v5.16：以前 secondary 页（所有内容/习惯/项目/复盘/搜索/设置）没有悬浮按钮，
      //   「随手记」在哪儿都写不了；现在二级页也有（底部导航还在，位置不变，不挡导航）。
      if (this.ready && !this.showQuick && !this.showMore && !this.dragging && !this.scrolling && !this.fabHide && !this.hideTabBar) {
        Column() {
          this.captureFab()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .padding({  right: S.space4Xl + this.sideInset, bottom: this.wideMode() ? (16 + this.bottomInset) : 68  })
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(60)
      }

      // 底部导航（只有窄屏才有；宽屏用左侧导航栏）
      if (this.ready && !this.hideTabBar && !this.wideMode()) {
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
          .padding({  left: S.space6Xl, right: S.space6Xl  })
          .onClick(() => {})
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(23,52,80,0.18)')
        .zIndex(95)
      }

      // v4.25：首启隐私弹窗已删除 —— 平台「标准化隐私声明托管服务」会弹系统的那个，
      // 我们再自建一个就会弹两次（AGC 审核不通过）。App 内仍保留
      // 《用户协议与隐私政策》的查看入口（设置页 → 查看用户协议与隐私政策）。

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
    .backgroundColor(tk(this.pal, 'bg'))
    // v4.6：量窗口宽度 → 定布局档位（折叠屏展开、平板横竖屏都会触发）
    .onAreaChange((oldA: Area, newA: Area) => {
      // v4.25：把窗口高度也报上去（弹层高度要按窗口算，见 utils/Responsive.ets 的 KEY_WH）
      R.update(this.numOf(newA.width), this.numOf(newA.height));
    })
  }
}
