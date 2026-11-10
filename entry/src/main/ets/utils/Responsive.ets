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
  /** 手机竖屏 / 折叠屏外屏（<600vp）：底部导航 + 单列 */
  static readonly Compact: number = 0;
  /** 折叠屏展开 / 平板竖屏（600–899vp）：左侧窄导航 + 单列 */
  static readonly Medium: number = 1;
  /** 平板横屏 / 大折叠屏（≥900vp）：左侧导航 + 多列网格（照网页端列数） */
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

  /** 内容区宽度（vp） */
  static contentW(): number {
    const v: number | undefined = AppStorage.get<number>(R.KEY_CW);
    return v === undefined ? 0 : v;
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

  /** 大屏（≥900vp）：可以按网页端的列数排多列 */
  static big(): boolean {
    return R.mode() >= Layout.Expanded;
  }

  /** 每一块占多宽（百分比字符串），直接给 .width() 用 */
  static colW(): string {
    const n: number = R.cols();
    if (n <= 1) { return '100%'; }
    if (n === 2) { return '48.4%'; }
    return '31.6%';
  }

  /** 首页大板块的宽度（照网页端 .home-grid 的 .span2 / .span1）
   *  · 3 列时：占 2 列的占 67.5%，占 1 列的占 31.5%（留 1% 当列间距）
   *  · 2 列时：占 2 列的占满整行，占 1 列的占一半
   *  · 1 列时：都占满
   */
  static span2(): string {
    if (R.cols() >= 3) { return '67.5%'; }
    return '100%';
  }

  static span1(): string {
    const n: number = R.cols();
    if (n >= 3) { return '31.5%'; }
    if (n === 2) { return '48.4%'; }
    return '100%';
  }

  /** 左侧导航栏宽度（vp）：网页端是 236px，这里按屏幕比例收一点 */
  static railW(): number {
    return R.big() ? 224 : 168;
  }

  /**
   * 窗口宽度（vp）→ 档位 + 列数，写进 AppStorage。
   * 宽度没变就不写（免得白白触发一次全 App 重画）。
   */
  static update(widthVp: number): void {
    const w: number = Math.round(widthVp);
    if (w <= 0) { return; }
    if (Math.abs(w - R.width()) < 1) { return; }
    let m: number = Layout.Compact;
    if (w >= 900) {
      m = Layout.Expanded;
    } else if (w >= 600) {
      m = Layout.Medium;
    }
    // 内容区宽度：宽屏要扣掉左侧导航栏和左右内边距
    const rail: number = m >= Layout.Medium ? (m >= Layout.Expanded ? 224 : 168) : 0;
    const pad: number = m >= Layout.Medium ? 32 : 0;
    const cw: number = w - rail - pad;
    // 列数：照网页端 .home-grid 的思路，一列至少 620vp、三列要 1120vp
    let cols: number = 1;
    if (cw >= 1120) {
      cols = 3;
    } else if (cw >= 620) {
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
   */
  static sheetBodyH(): number {
    return Math.round(R.screenH() * 0.56);
  }
}
