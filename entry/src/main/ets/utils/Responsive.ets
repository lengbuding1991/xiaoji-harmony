// entry/src/main/ets/utils/Responsive.ets
// v4.6：宽屏适配的总开关。
//
// 平板 / 折叠屏展开后，App 不能再「手机版拉宽」——那是一堆 1000vp 宽的卡片，
// 看起来就是你说的「拉宽了，很难看」。网页端「个人工作台」的做法是：
// 左边一列 236px 的导航，右边内容区按网格分列（KPI 5 列、首页 3 列、
// 设置 2 列……）。这个文件就是把那套做法搬进 App 的第一层：
//   · 按「内容区宽度（vp）」算档位和列数；
//   · 写进 AppStorage，各页面用 @StorageLink 读，读到就重画；
//   · 折叠屏展开/折叠、板横竖屏、分屏，全都只改窗口宽度 ⇒ 一处判断全 App 生效。
//
// 为什么按宽度而不是按「是不是平板」：平板开多窗口时窗口很窄，
// 按设备类型判断会把窄窗口也当成平板排版，那就更难看了。

import { display } from '@kit.ArkUI';

export class Layout {
  /** 手机竖屏 / 折叠屏外屏（<640vp）：底部导航 + 单列 */
  static readonly Compact: number = 0;
  /** 折叠屏展开 / 平板竖屏（640–980vp）：左侧图标导航 + 单到双列 */
  static readonly Medium: number = 1;
  /** 平板横屏 / 大折叠屏（>980vp）：左侧带文字导航 + 多列网格（照网页端列数） */
  static readonly Expanded: number = 2;
}

export class R {
  /** 布局档位（AppStorage） */
  static readonly KEY_MODE: string = 'wb_layout';
  /** 当前窗口宽度（vp，AppStorage） */
  static readonly KEY_W: string = 'wb_width';
  /** 内容区宽度（扣掉左侧导航和内边距，vp，AppStorage） */
  static readonly KEY_CW: string = 'wb_content_w';
  /** 内容区列数（AppStorage） */
  static readonly KEY_COLS: string = 'wb_cols';
  /**
   * 当前**窗口**高度（vp，AppStorage）。
   *
   * v4.25 新增：之前算弹层高度用的是「屏幕高度」（display.getDefaultDisplaySync），
   * 但窗口高度 ≠ 屏幕高度 —— 平板分屏、悬浮窗、横屏时，窗口比屏幕矮一大截，
   * 于是弹层比窗口还高，底下的「保存」按钮被挤出屏幕，点不到
   * （AGC 审核在 MatePad Pro 上报的「无法滑动到底部、无法添加成功任务」就是这个）。
   * ⇒ 改成记窗口自己的高度（Index.ets 根节点的 onAreaChange 量得到）。
   */
  static readonly KEY_WH: string = 'wb_window_h';

  /** 读当前档位 */
  static mode(): number {
    const v: number | undefined = AppStorage.get<number>(R.KEY_MODE);
    return v === undefined ? Layout.Compact : v;
  }

  /** 读当前窗口宽度（vp） */
  static width(): number {
    const v: number | undefined = AppStorage.get<number>(R.KEY_W);
    return v === undefined ? 0 : v;
  }

  /**
   * 当前**窗口**高度（vp）。
   * 取不到（还没量到）就退回屏幕高度，至少不会算出 0 把弹层压扁。
   */
  static windowH(): number {
    const v: number | undefined = AppStorage.get<number>(R.KEY_WH);
    if (v === undefined || v <= 0) { return R.screenH(); }
    return v;
  }

  /** 内容区列数 */
  static cols(): number {
    const v: number | undefined = AppStorage.get<number>(R.KEY_COLS);
    return v === undefined ? 1 : v;
  }

  /** 宽屏（≥600vp）：用左侧导航，不再用底部导航 */
  static wide(): boolean {
    return R.mode() >= Layout.Medium;
  }

  /**
   * 左侧导航栏宽度（vp）：网页端是 236px，这里按屏幕比例收一点。
   *
   * v4.26：窗口 < 980vp（平板竖屏 960vp 就是这个情况）时，
   *   照网页端 `@media(max-width:980px){.side{width:70px} main{margin-left:70px}}`
   *   收成 70vp 的图标栏 —— 否则 224vp 的导航把 960vp 的窗口切掉一大块，
   *   内容区只剩 704vp，首页被挤成窄列、卡片之间出现大片空白（用户在平板竖屏下报的）。
   */
  static railW(): number {
    if (!R.wide()) {
      return 0;
    }
    // v5.17：照网页端 @media(max-width:980px){.side{width:70px}}。
    //   以前这里是「70 / 224 / 168」三档，而且 168 档给了 600–899vp ——
    //   结果窗口越宽侧栏反而越窄（900vp 给 70 图标栏，899vp 给 168 带文字栏），断点倒挂。
    return R.width() > 980 ? 224 : 70;
  }

  /** 窄导航（只留图标）：网页端 980vp 断点 */
  static railCompact(): boolean {
    const w: number = R.width();
    return w > 0 && w <= 980;
  }

  /**
   * 页面底部要留多少白（vp）。
   *
   * v5.17：以前到处写死 `S.pageBottom`（92vp），那是给手机底部导航留的。
   *   宽屏（平板 / 折叠屏）走的是左侧导航，**根本没有底部导航**，
   *   那 92vp 就是白白扔掉的一屏空间 ⇒ 宽屏只留 24vp。
   */
  static bottomPad(): number {
    return R.wide() ? 24 : 92;
  }

  /**
   * 窗口宽度（vp）→ 档位 + 列数，写进 AppStorage。
   * 宽度没变就不写（免得白白触发一次全 App 重画）。
   * v4.25：多带一个窗口高度（弹层高度要用它，见 KEY_WH）。
   */
  static update(widthVp: number, heightVp: number = 0): void {
    const w: number = Math.round(widthVp);
    const h: number = Math.round(heightVp);
    if (w <= 0) { return; }
    if (h > 0) {
      AppStorage.set<number>(R.KEY_WH, h);
    }
    if (Math.abs(w - R.width()) < 1) { return; }
    // v5.17：断点全部照网页端 app/globals.css 的 @media 改：
    //   ≤640px  侧栏变底部导航（.side{bottom:0;height:60px}）
    //   ≤980px  .side{width:70px}（只留图标）
    //   ≤1180px .home-grid 两列
    //   ≤820px  .home-grid 一列
    // 以前用 600 / 900 两档，和网页端对不上，出来「平板竖屏反而比大屏窄」。
    let m: number = Layout.Compact;
    if (w > 980) {
      m = Layout.Expanded;
    } else if (w >= 640) {
      m = Layout.Medium;
    }
    // 内容区宽度：宽屏要扣掉左侧导航栏和左右内边距
    const rail: number = m >= Layout.Medium ? (w > 980 ? 224 : 70) : 0;
    const pad: number = m >= Layout.Medium ? 32 : 0;
    const cw: number = w - rail - pad;
    // 列数：照网页端 .home-grid（按视口宽，不是内容区宽）
    let cols: number = 1;
    if (w > 1180) {
      cols = 3;
    } else if (w > 820) {
      cols = 2;
    }
    AppStorage.setOrCreate<number>(R.KEY_W, w);
    AppStorage.setOrCreate<number>(R.KEY_CW, cw);
    AppStorage.setOrCreate<number>(R.KEY_COLS, cols);
    AppStorage.setOrCreate<number>(R.KEY_MODE, m);
  }

  /** 屏幕高度（vp）。取不到就用 800 兜底 */
  static screenH(): number {
    try {
      const d = display.getDefaultDisplaySync();
      const dp: number = d.densityPixels > 0 ? d.densityPixels : 3.5;
      return Math.round(d.height / dp);
    } catch (e) {
      return 800;
    }
  }

  /**
   * 底部抽屉里「表单区」能给多高（vp）。
   *
   * 为什么不能写百分比（v4.11 踩到）：
   *   抽屉是 SheetSize.FIT_CONTENT（高度由内容决定），而里面的 Scroll 写
   *   `constraintSize({ maxHeight: '68%' })` 时，ArkUI 会去找「最近的有确定高度的祖先」——
   *   抽屉面板此刻的高度正是由这个 Scroll 决定的（循环依赖），
   *   于是百分比落到一个莫名其妙的小值上：新建项目抽屉只剩 236vp 高，
   *   五栏表单只能露出两栏，底下的「属于哪一块 / 颜色 / 目标日」全被切掉。
   *   ⇒ 换成按屏幕高度算出来的**绝对 vp 数**，不依赖任何祖先的高度。
   *
   * v4.25：而且要按**窗口**高度算，不是屏幕高度。
   *   平板横屏 / 分屏 / 悬浮窗时窗口比屏幕矮，按屏幕算出来的抽屉会高出窗口，
   *   底下的「保存」按钮被挤出屏幕 ⇒ 审核在 MatePad Pro 上判「无法添加成功任务」。
   */
  static sheetBodyH(): number {
    return Math.max(160, Math.round(R.windowH() * 0.56));
  }

  /**
   * 宽屏弹层（居中卡片）整块能给多高（vp）。
   * 卡片 = 头部 + 表单区 + 底部按钮条，三块加起来不能超过它，否则按钮条会被切掉。
   */
  static sheetMaxH(): number {
    return Math.max(260, Math.round(R.windowH() - 24));
  }
}
