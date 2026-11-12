import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { Boot } from '../db/Boot';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /** 冷启动时从通知 Want 带来的页面，等 loadContent 成功、UI 就绪后再写进 AppStorage */
  private launchPage: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // v4.0：全部数据在本机。onCreate 里先把本地库打开并建好表，
    // 页面渲染时直接读本地库，不会闪「加载中」。
    // v4.4：记录灵感的编辑器弹窗状态放在 AppStorage 里
    // （@StorageLink 要求 key 先存在，否则运行时报错）
    AppStorage.setOrCreate<boolean>('wb_note_editor_open', false);
    AppStorage.setOrCreate<boolean>('wb_dragging', false);
    AppStorage.setOrCreate<boolean>('wb_scrolling', false);
    AppStorage.setOrCreate<boolean>('wb_fab_hide', false);
    // v4.6：宽屏布局档位 + 窗口宽度（@StorageLink 要求 key 先存在）
    AppStorage.setOrCreate<number>('wb_layout', 0);
    AppStorage.setOrCreate<number>('wb_width', 0);
    AppStorage.setOrCreate<number>('wb_content_w', 0);
    AppStorage.setOrCreate<number>('wb_cols', 1);
    AppStorage.setOrCreate<number>('wb_side_inset', 0);
    // v4.25：当前窗口高度（弹层高度按它算，不按屏幕高度算）
    AppStorage.setOrCreate<number>('wb_window_h', 0);
    // v4.24：边界提示胶囊（@StorageLink 要求 key 先存在）
    AppStorage.setOrCreate<string>('wb_edge_hint_text', '');
    AppStorage.setOrCreate<number>('wb_edge_hint_side', 0);
    AppStorage.setOrCreate<number>('wb_edge_hint_seq', 0);
    this.launchPage = this.pageFromWant(want);
    // 本地库闸门：开库 + 建表 + 铺示例数据，只做一次；页面等 Boot.when() 再读数据
    Boot.start(this.context);
    this.dbReady = Boot.when();
    hilog.debug(DOMAIN, 'workbench', '%{public}s', 'Ability onCreate, local db opening');
  }

  private dbReady: Promise<void> = Promise.resolve();

  /** 页面可以调用：等本地库就绪（页面用它避免空库一闪） */
  waitDb(): Promise<void> {
    return this.dbReady;
  }

  onDestroy(): void {
    hilog.debug(DOMAIN, 'workbench', '%{public}s', 'Ability onDestroy');
  }

  /** 允许深链打开的页面（白名单）
   *  v4.4：以前不校验，非法 page 会一路走到 Index 的兜底分支，渲染出一个「更多」死页面。
   */
  private static readonly DEEP_PAGES: string[] =
    ['home', 'tasks', 'calendar', 'notes', 'all', 'habits', 'projects', 'review', 'stats', 'search', 'settings'];

  /** v4.20：从深链 Want.parameters 里读出目标页面（wb_page） */
  private pageFromWant(want: Want): string {
    try {
      const p = want.parameters;
      if (!p) { return ''; }
      const raw: Object | undefined = p['wb_page'];
      if (raw === undefined || raw === null) { return ''; }
      const page: string = String(raw);
      for (const ok of EntryAbility.DEEP_PAGES) {
        if (ok === page) { return page; }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /** UI 已加载完：把冷启动深链写进 AppStorage（@StorageLink 会收到） */
  private afterUiReady(): void {
    try {
      if (this.launchPage.length > 0) {
        AppStorage.setOrCreate<string>('wb_open_page', this.launchPage);
        AppStorage.setOrCreate<number>('wb_dl_nonce', Date.now());
        this.launchPage = '';
      }
    } catch (e) {
      hilog.error(DOMAIN, 'workbench', 'deepLink failed: %{public}s', JSON.stringify(e));
    }
    // v4.20：零权限 —— 不再申请任何系统权限，这里只处理深链。
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.debug(DOMAIN, 'workbench', '%{public}s', 'Ability onWindowStageCreate');

    // 底部导航要贴到屏幕最下沿：先量出系统导航条的高度（px），
    // 换成 vp 存进 AppStorage，页面用它给导航栏加一段下内边距。
    try {
      const main: window.Window = windowStage.getMainWindowSync();
      const density: number = display.getDefaultDisplaySync().densityPixels;
      // 实测这台设备：TYPE_SYSTEM / TYPE_SYSTEM_GESTURE 的 bottom 都是 0，
      // 真正挡在屏幕底部的是导航指示条（TYPE_NAVIGATION_INDICATOR = 98px）。
      // 三种都量一遍，取最大的那个，换算成 vp 存进 AppStorage。
      const sys = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const gest = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE);
      const ind = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      let bottomPx: number = sys.bottomRect.height;
      if (gest.bottomRect.height > bottomPx) { bottomPx = gest.bottomRect.height; }
      if (ind.bottomRect.height > bottomPx) { bottomPx = ind.bottomRect.height; }
      if (bottomPx > 0 && density > 0) {
        const bottomVp: number = Math.round(bottomPx / density);
        AppStorage.setOrCreate<number>('wb_bottom_inset', bottomVp);
        hilog.debug(DOMAIN, 'workbench', 'bottom inset = %{public}s vp (px=%{public}s density=%{public}s)',
          `${bottomVp}`, `${bottomPx}`, `${density}`);
      }
      // v4.6：平板横屏时系统导航条在左右两侧，量出来给悬浮按钮让位
      let sidePx: number = Math.max(sys.leftRect.width, sys.rightRect.width,
        gest.leftRect.width, gest.rightRect.width);
      if (ind.leftRect.width > sidePx) { sidePx = ind.leftRect.width; }
      if (ind.rightRect.width > sidePx) { sidePx = ind.rightRect.width; }
      if (sidePx > 0 && density > 0) {
        const sideVp: number = Math.round(sidePx / density);
        AppStorage.setOrCreate<number>('wb_side_inset', sideVp);
        hilog.debug(DOMAIN, 'workbench', 'side inset = %{public}s vp', `${sideVp}`);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'workbench', 'read bottom inset failed: %{public}s', JSON.stringify(e));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'workbench', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.debug(DOMAIN, 'workbench', 'Succeeded in loading the content.');
      this.afterUiReady();
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'workbench', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /** 热启动：App 在前台/后台时收到深链，走这里；用 AppStorage 唤醒页面里的 @StorageLink */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const page: string = this.pageFromWant(want);
    if (page.length > 0) {
      try {
        AppStorage.setOrCreate<string>('wb_open_page', page);
        AppStorage.setOrCreate<number>('wb_dl_nonce', Date.now());
      } catch (e) {
        hilog.error(DOMAIN, 'workbench', 'onNewWant failed: %{public}s', JSON.stringify(e));
      }
    }
    hilog.debug(DOMAIN, 'workbench', 'Ability onNewWant, page=%{public}s', page);
  }

  onWindowStageDestroy(): void {
    hilog.debug(DOMAIN, 'workbench', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.debug(DOMAIN, 'workbench', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.debug(DOMAIN, 'workbench', '%{public}s', 'Ability onBackground');
  }
}
