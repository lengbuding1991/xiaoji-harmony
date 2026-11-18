// entry/src/main/ets/utils/Theme.ets
// 尺寸与取色规则。v5.7 起不再有「明/暗」两套，只有 5 套配色方案（见 utils/Palette.ets）。
// 改这里之前请先看工作台那份 CSS，两边必须同步，否则界面会立刻「不像」。

import { PALETTES, PALETTE_COUNT, DEFAULT_PALETTE, PaletteDef } from './Palette';

/**
 * v5.7 配色方案
 *  - 开关存在 AppStorage['wb_pal']（0..4），设置页写入、启动时由 Store.restorePalette() 恢复
 *  - 索引 4（雾紫冷调）= 老版本唯一的浅色配色，老用户升级后界面一个像素都不变
 *  - tk(pal, token)：主题 token（bg / card / text …）按配色取值
 *  - tc(pal, hex, kind)：写死的颜色按用途换算（0 底色 / 1 文字 / 2 描边）
 *  注意：ArkUI V1 只有「属性表达式里直接读过 state」的节点才会重画，
 *  所以取色必须把 this.pal 传进来，切换配色才会立刻生效。
 */

/** 取某套配色；越界一律回落到默认那套 */
function palOf(pal: number): PaletteDef {
  const i = (pal < 0 || pal >= PALETTE_COUNT) ? DEFAULT_PALETTE : Math.floor(pal);
  return PALETTES[i];
}

/** 当前生效的配色索引（给「方法内部取色」用，例如 buildRows 这类要先算再写 @State 的地方） */
export function curPal(): number {
  const v: number | undefined = AppStorage.get<number>('wb_pal');
  if (v === undefined || v < 0 || v >= PALETTE_COUNT) {
    return DEFAULT_PALETTE;
  }
  return Math.floor(v);
}

/** 主题 token：bg / card / text / brand … */
export function tk(pal: number, token: string): string {
  const p: PaletteDef = palOf(pal);
  return p.map[token] ?? token;
}

/** 压在底色上的文字色（品牌色的深色版，保证 >= 4.5:1） */
export function tkInk(pal: number, token: string): string {
  const p: PaletteDef = palOf(pal);
  return p.ink[token] ?? p.map[token] ?? token;
}

/** 画在「填充底」上的文字色：五套配色的填充底都压深到 >= 4.6:1，统一白字 */
export function onFill(pal: number): string {
  const p: PaletteDef = palOf(pal);
  return p.misc['onFill'] ?? '#FFFFFF';
}

/**
 * 写死的颜色按用途换算
 *  kind 0 = 底色 / 填充   kind 1 = 文字   kind 2 = 描边
 *  找不到对应换算就原样返回（这样换配色时不会把没登记的颜色改坏）
 */
export function tc(pal: number, hex: string, kind: number): string {
  const p: PaletteDef = palOf(pal);
  const raw: string = hex.replace('#', '').toUpperCase();
  if (kind === 1) {
    const deep: string | undefined = p.textRemap[raw];
    if (deep !== undefined) { return deep; }
    return hex;
  }
  if (kind === 0) {
    const sink: string | undefined = p.surfRemap[raw];
    if (sink !== undefined) { return sink; }
    return hex;
  }
  const edge: string | undefined = p.borderRemap[raw];
  if (edge !== undefined) { return edge; }
  return hex;
}

/** #RRGGBB → rgba(r,g,b,a)（背景光斑这类要调透明度的场景用） */
export function rgbaOf(hex: string, alpha: number): string {
  const h: string = hex.replace('#', '');
  const r: number = parseInt(h.substring(0, 2), 16);
  const g: number = parseInt(h.substring(2, 4), 16);
  const b: number = parseInt(h.substring(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

/**
 * 尺寸刻度（v5.16：全 App 只有这一张表，页面里不再写裸数字）
 *
 * 圆角 8 档：2.5 小圆点 / 5 徽章 / 9 小标签 / 11 按钮 / 13 卡内块 / 20 卡片 / 22 弹层 / 999 胶囊
 * 间距 10 档：2 的步进（2→20）
 * 字号 21 档：0.5 的步进（8.5→30）
 */
export class S {
  // ---- 圆角 ----
  static readonly radiusDot: number = 2.5;    // 小圆点：状态点、进度点
  static readonly radiusXs: number = 5;       // 徽章、小标签
  static readonly radiusSm: number = 9;       // 小标签、chip
  static readonly radiusBtn: number = 11;     // 按钮
  static readonly radiusInner: number = 13;   // 卡片内的块（.tcard / .mod / .tstat）
  static readonly radiusCard: number = 20;    // 卡片
  static readonly radiusSheet: number = 22;   // 弹层顶部
  static readonly radiusPill: number = 999;   // 胶囊

  // ---- 间距（2vp 步进，flex space / padding / margin 共用）----
  static readonly spaceXs: number = 2;
  static readonly spaceSm: number = 4;
  static readonly spaceMd: number = 6;
  static readonly spaceLg: number = 8;
  static readonly spaceXl: number = 10;
  static readonly space2Xl: number = 12;
  static readonly space3Xl: number = 14;
  static readonly space4Xl: number = 16;
  static readonly space5Xl: number = 18;
  static readonly space6Xl: number = 20;

  static readonly gap: number = 12;            // = space2Xl
  static readonly gapLg: number = 14;          // = space3Xl，.home-grid gap
  static readonly padCard: number = 0;         // 用 headPad/bodyPad 分区，见 Card
  static readonly headPadH: number = 14;       // .c-head padding: 13px 14px 0
  static readonly headPadT: number = 13;
  static readonly bodyPadH: number = 14;       // .c-body padding: 10px 14px 14px
  static readonly bodyPadT: number = 10;
  static readonly bodyPadB: number = 14;
  static readonly pagePad: number = 13;        // main padding 左右
  static readonly pageTop: number = 16;
  static readonly pageBottom: number = 92;     // 给底部导航留白
  static readonly tabBarH: number = 52;        // 工作台手机端是 17px 图标 + 9px 文字的小标签

  // ---- 字号 ----
  static readonly hiddenSize: number = 1;      // 不可见的刷新标记（1px 透明文字）
  static readonly microSize: number = 8.5;     // 极小角标
  static readonly tinySize: number = 9.5;      // .meta / .kpi-top
  static readonly subSize: number = 10.5;      // 次要说明
  static readonly labelSize: number = 11;      // 标签、按钮文字、chip
  static readonly smallSize: number = 12;      // 卡片内小字 —— **错误提示的最小字号，不许再小**
  static readonly bodySize: number = 12.5;     // .tt 正文
  static readonly midSize: number = 13.5;      // 次级小标题
  static readonly cardTitleSize: number = 14;  // .c-head h2
  static readonly headSize: number = 15;       // 小标题
  static readonly iconSize: number = 16;       // 常规图标
  static readonly sectionSize: number = 17;    // 区块标题、输入框字号
  static readonly dialogSize: number = 19;     // 弹层标题
  static readonly heroIconSize: number = 20;   // 大图标
  static readonly numberSize: number = 22;     // .kpi b 数字
  static readonly pageTitleSize: number = 23;  // 每个页面顶部的大标题
  static readonly titleSize: number = 25;      // 首页大标题
  static readonly bigNumber: number = 26;
  static readonly heroNumberSize: number = 29; // 超大数字
  static readonly iconXLSize: number = 30;     // 超大图标
}

/** 领域色的「标签」配色（工作台 catStyle：浅底 + 深字） */
export function catBg(pal: number, area: string): string {
  const p: PaletteDef = palOf(pal);
  return p.catbg[area] ?? p.catbg['work'] ?? '#E8F2FC';
}

export function catColor(pal: number, area: string): string {
  const p: PaletteDef = palOf(pal);
  return p.catfg[area] ?? p.catfg['work'] ?? '#2970AD';
}

/** 领域色（圆点 / 描边 / 甘特块用） */
export function areaColor(pal: number, area: string): string {
  const p: PaletteDef = palOf(pal);
  switch (area) {
    case 'side': return p.map['side'] ?? p.map['work'] ?? '#3A5FA8';
    case 'media': return p.map['media'] ?? p.map['work'] ?? '#3A5FA8';
    case 'study': return p.map['study'] ?? p.map['work'] ?? '#3A5FA8';
    case 'life': return p.map['life'] ?? p.map['work'] ?? '#3A5FA8';
    default: return p.map['work'] ?? '#3A5FA8';
  }
}

/** 领域中文名 */
export function areaLabel(area: string): string {
  switch (area) {
    case 'work': return '工作';
    case 'side': return '副业';
    case 'media': return '自媒体';
    case 'study': return '学习';
    case 'life': return '生活';
    default: return '其他';
  }
}

/** 领域色的横条底 / 条上文字 */
export function barBg(pal: number, area: string): string {
  const p: PaletteDef = palOf(pal);
  return p.barbg[area] ?? p.barbg['_'] ?? '#E4F1FB';
}

export function barColor(pal: number, area: string): string {
  const p: PaletteDef = palOf(pal);
  return p.barfg[area] ?? p.barfg['_'] ?? '#387199';
}

/** 状态中文名 */
export function statusLabel(s: string): string {
  if (s === 'todo') { return '待办'; }
  if (s === 'doing') { return '进行中'; }
  if (s === 'done') { return '完成'; }
  return '待办';
}

export function statusColor(pal: number, s: string): string {
  if (s === 'todo') { return tk(pal, 'todo'); }
  if (s === 'doing') { return tk(pal, 'doing'); }
  if (s === 'done') { return tk(pal, 'brand'); }
  return tk(pal, 'textHint');
}

/** 优先级中文名 */
export function priorityLabel(p: string): string {
  if (p === 'high') { return '要紧'; }
  if (p === 'med') { return '普通'; }
  return '随手';
}

export function priorityColor(pal: number, p: string): string {
  if (p === 'high') { return '#D2795C'; }
  if (p === 'med') { return tk(pal, 'textFaint'); }
  return tk(pal, 'textHint');
}

/** 卡片的投影（阴影颜色跟着配色的主色走） */
export function cardShadow(pal: number): ShadowOptions {
  const p: PaletteDef = palOf(pal);
  return {
    radius: 36,
    color: `rgba(${p.misc['shadowRgb'] ?? '37,84,133'},0.11)`,
    offsetX: 0,
    offsetY: 14
  };
}

/** 顶栏 / 底栏的毛玻璃 */
export function glassEffect(radius: number): BackgroundEffectOptions {
  return {
    radius: radius,
    saturation: 1.7,
    brightness: 1.06,
    color: 'rgba(255,255,255,0.84)'
  };
}

/** 弹层的投影 */
export function sheetShadow(pal: number): ShadowOptions {
  const p: PaletteDef = palOf(pal);
  return {
    radius: 50,
    color: `rgba(${p.misc['shadowRgb'] ?? '37,84,133'},0.18)`,
    offsetX: 0,
    offsetY: 12
  };
}

/** 底部弹层的投影（往上打） */
export function sheetShadowUp(pal: number): ShadowOptions {
  const p: PaletteDef = palOf(pal);
  return {
    radius: 50,
    color: `rgba(${p.misc['shadowRgb'] ?? '37,84,133'},0.18)`,
    offsetX: 0,
    offsetY: -12
  };
}

/** 品牌渐变（渐变主色 → 渐变辅色） */
export function brandGradient(pal: number): LinearGradient {
  const p: PaletteDef = palOf(pal);
  return {
    angle: 140,
    colors: [[p.map['gradFrom'] ?? '#6548AC', 0], [p.map['gradTo'] ?? '#46539F', 1]]
  };
}

/** 进度条 / 轨道渐变（品牌色 → 品牌深色） */
export function trackGradient(pal: number): LinearGradient {
  const p: PaletteDef = palOf(pal);
  return {
    angle: 90,
    colors: [[p.map['brand'] ?? '#523593', 0], [p.map['brandDeep'] ?? '#3F2675', 1]]
  };
}

/** 迷你趋势柱的渐变（浅色块 → 更浅） */
export function miniGradient(pal: number): LinearGradient {
  const p: PaletteDef = palOf(pal);
  return {
    angle: 180,
    colors: [[p.mini[0] ?? '#BFEAF8', 0], [p.mini[1] ?? '#E4F4FC', 1]]
  };
}

/** 首页背景的五团光斑色（配合 rgbaOf 调透明度） */
export function blobColors(pal: number): string[] {
  const p: PaletteDef = palOf(pal);
  return p.blobs;
}

/** 热力格 / 领域色数组等「一组颜色」统一从配色里取 */
export function paletteList(pal: number, group: string): string[] {
  const p: PaletteDef = palOf(pal);
  if (group === 'heat') { return p.heat; }
  if (group === 'heatSoft') { return p.heatSoft; }
  if (group === 'kindFg') { return p.kindFg; }
  if (group === 'kindBg') { return p.kindBg; }
  if (group === 'spark5') { return p.spark5; }
  if (group === 'domain5') { return p.domain5; }
  if (group === 'project8') { return p.project8; }
  if (group === 'entryBg') { return p.entryBg; }
  if (group === 'entryFg') { return p.entryFg; }
  return p.series;
}

/** 配色里登记的一项「零散色」（轴标字色、分隔线、逾期底色等） */
export function misc(pal: number, key: string, fallback: string): string {
  const p: PaletteDef = palOf(pal);
  return p.misc[key] ?? fallback;
}

/** 取某组颜色里的第 i 个 */
export function paletteAt(pal: number, group: string, i: number): string {
  const arr: string[] = paletteList(pal, group);
  if (i < 0 || i >= arr.length) { return arr[0] ?? '#3A5FA8'; }
  return arr[i];
}
