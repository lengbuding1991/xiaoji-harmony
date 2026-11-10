// entry/src/main/ets/utils/Theme.ets
// 色值与尺寸逐条对齐「个人工作台」app/globals.css 的 :root 变量与 .card/.kpi 等规则。
// 改这里之前请先看工作台那份 CSS，两边必须同步，否则界面会立刻「不像」。


/**
 * v4.8 深色模式
 *  - 开关存在 AppStorage['wb_dark']，设置页写入、启动时由 EntryAbility 恢复
 *  - tk(dark, token)：主题 token（bg / card / text …）在明暗两套色板里取值
 *  - tc(dark, hex, kind)：写死的颜色按用途换算（0 底色 / 1 文字 / 2 描边）
 *  注意：ArkUI V1 只有「属性表达式里直接读过 state」的节点才会重画，
 *  所以取色必须把 this.dark 传进来，切换主题才会立刻生效。
 */
export function isDark(): boolean {
  return AppStorage.get<boolean>('wb_dark') === true;
}

const LIGHT_MAP: Record<string, string> = {
  'bg': '#EFF6FC',
  'card': '#FFFFFF',
  'card2': '#FBFDFF',
  'cardBorder': '#EDF4FA',
  'line': '#E6EFF8',
  'divider': '#E6EFF8',
  'soft': '#F4F9FE',
  'track': '#EEF5FA',
  'text': '#1D2A38',
  'textSub': '#596879',
  'textFaint': '#55687C',
  'textHint': '#52697E',
  'textPale': '#4D6A82',
  'brand': '#12706B',
  'brandDeep': '#0F6B66',
  'brandSoft': '#E1F7F5',
  'brandLine': '#BCE9E6',
  'gradFrom': '#1C7C74',
  'gradTo': '#1B7799',
  'brandTint': '#E3F7F6',
  'work': '#1A6499',
  'side': '#6650C8',
  'media': '#A54A1E',
  'study': '#0F6E58',
  'life': '#8A5A0F',
  'event': '#276AA4',
  'danger': '#A64B2E',
  'dangerSoft': '#FBEDE9',
  'done': '#0F6E58',
  'doing': '#8A5A0F',
  'todo': '#1A6499',
  'heat0': '#EDF4FA',
  'checkRing': '#D6E4F0',
  'doingSoft': '#FBF1D8',
  'doingLine': '#EFD08A',
  'doneDeep': '#E1F7F5',
};

const DARK_MAP: Record<string, string> = {
  'bg': '#0E1620',
  'card': '#16202C',
  'card2': '#1B2735',
  'cardBorder': '#24313F',
  'line': '#223040',
  'divider': '#223040',
  'soft': '#1A2532',
  'track': '#1E2A38',
  'text': '#E8EFF7',
  'textSub': '#93A6B8',
  'textFaint': '#899BAC',
  'textHint': '#8B9AAA',
  'textPale': '#8A9AAC',
  'brand': '#3AC8C2',
  'brandDeep': '#57D8D0',
  'brandSoft': '#16302F',
  'brandLine': '#24504C',
  'gradFrom': '#4FD3C8',
  'gradTo': '#33A9D6',
  'brandTint': '#153030',
  'work': '#6FB2F0',
  'side': '#B79BFB',
  'media': '#FFB79B',
  'study': '#7FE0C9',
  'life': '#FFD066',
  'event': '#A5D4F5',
  'danger': '#F09A7E',
  'dangerSoft': '#33211C',
  'done': '#7FE0C9',
  'doing': '#FFD066',
  'todo': '#6FB2F0',
  'heat0': '#1B2735',
  'checkRing': '#34455A',
  'doingSoft': '#33291A',
  'doingLine': '#6B5622',
  'doneDeep': '#16302F',
};

/**
 * v4.22：浅色模式下「填充/底色」的压深表。
 * tc(dark, hex, 0) 走这里 —— 浅色时把旧的亮色底换成压深值，深色时走 SURF_MAP。
 * 这样 `tc(this.dark, '#3AC8C2', 0)` 这种直写填充色不用逐个改字面量。
 * 每个值都保证「白字压上去 >= 4.6:1」。
 */
const LIGHT_SURF_MAP: Record<string, string> = {
  '3AC8C2': '#12706B',
  '1F9E9A': '#0F6B66',
  '4FD3C8': '#1C7C74',
  '33A9D6': '#1B7799',
  '5AD7C9': '#12706B',
  '6FD6BE': '#0F6E58',
  '7FE3D6': '#0F6E58',
  'E08A6F': '#A64B2E',
  'E89079': '#9E4A31',
  'D2795C': '#9E4A31',
  '5AA7E8': '#1A6499',
  'A78BFA': '#6650C8',
  'F5AE8E': '#A54A1E',
  'F6C453': '#8A5A0F',
  '8FC7EE': '#276AA4',
  'F49AC1': '#A54A7A',
};

const SURF_MAP: Record<string, string> = {

  '3AC8C2': '#2D5D5B',
  'C9D8E6': '#24313F',
  'E08A6F': '#5D382D',
  'E1F7F5': '#16302F',
  'E3EDF7': '#16273A',
  'E89079': '#5D372D',
  'E9F3FB': '#16273A',
  'E9F7F6': '#16302F',
  'EAF2FA': '#16273A',
  'EAF8F6': '#16302F',
  'EDF5FB': '#1C2735',
  'EEF5FA': '#1E2A38',
  'EFF7FB': '#1C2735',
  'EFF9F8': '#14262A',
  'F2F7FB': '#19242F',
  'F2FBF9': '#14262A',
  'F4F9FD': '#1A2532',
  'F5FAFD': '#1A2532',
  'F6FAFE': '#19242F',
  'F6FBFE': '#19242F',
  'F7FBFE': '#17222E',
  'F8FBFE': '#17222E',
  'F8FCFF': '#17222E',
  'FAFCFE': '#17222E',
  'FBFDFF': '#1B2735',
  'FDF0EE': '#33211C',
  'FDF2EF': '#33211C',
  'FDF4DC': '#33291A',
  'FDFEFF': '#17222E',
  'FEF3F0': '#33211C',
  'FFF8EC': '#33291A',
  'FFFFFF': '#16202C',
  '7FE3D6': '#217369',
  'A9BECF': '#242E35',
  'C9DAE6': '#212F38',
  'DFF3F8': '#19282B',
  'EAF4FC': '#141B21',
  'EDF4FA': '#141B21',
  'F1F7FC': '#141B21',
  'F2F8FD': '#141B21',
  'F4F9FE': '#141B21',
  'F6FAFD': '#141C21',
  'F8FDFC': '#14211F',
  'FDEDEA': '#211614',
};

const TEXT_MAP: Record<string, string> = {

  '17A8A4': '#57D8D0',
  '1B7F76': '#57D8D0',
  '1D2A38': '#E8EFF7',
  '1F6E77': '#57D8D0',
  '1F9E9A': '#57D8D0',
  '2B4055': '#C9D8E6',
  '2C4257': '#C9D8E6',
  '2E4A5E': '#B7C7D4',
  '33485A': '#B7C7D4',
  '3A4D5F': '#B7C7D4',
  '3A4E60': '#B7C7D4',
  '3AC8C2': '#94D1CF',
  '3D7BA6': '#7FB6F0',
  '4E6579': '#93A6B6',
  '4E6C86': '#93A6B6',
  '5C7086': '#9DB0C1',
  '5E7183': '#9DB0C1',
  '6A7F92': '#9DB0C1',
  '6E8497': '#93A6B6',
  '78899C': '#93A6B8',
  '7C8F9F': '#93A6B6',
  '7C93A6': '#93A6B6',
  '8095A8': '#93A6B6',
  '8FA2B3': '#A3B4C4',
  '9BAEBD': '#8FA1B2',
  '9BAFC0': '#8FA1B2',
  '9DB0C1': '#B7C7D4',
  '9FB2C2': '#8FA1B2',
  '9FE0DC': '#80C2BE',
  'A2B3C2': '#8FA1B2',
  'A8B8C6': '#93A6B8',
  'A97C1B': '#FFD066',
  'A9BCCA': '#8AA4B7',
  'B0563C': '#E8A98F',
  'B4483C': '#E98C77',
  'B6C7D4': '#8FA1B2',
  'B6C8D6': '#8FA1B2',
  'B7C7D4': '#8FA1B2',
  'B9C9D6': '#8FA1B2',
  'B9CAD8': '#8FA1B2',
  'C2D0DB': '#8FA1B2',
  'C89A5B': '#E0BE8A',
  'D2795C': '#F0A288',
  'D4705F': '#F09A85',
  'E0B4A4': '#C99A8C',
  '1F5E7A': '#70BEE1',
  '2F6C8A': '#92C5DF',
  '2FA9A3': '#A6EAE7',
  '54697C': '#B7C4D0',
  '7E93A6': '#BAC6D0',
  '8FA3B6': '#CDD6DE',
  '93A6B6': '#CED7DE',
  'A3B3C1': '#CED7DE',
  'A9C0D2': '#C9D8E3',
  'B06A5C': '#D1A9A1',
  'C25E4A': '#DCA296',
  'C3D2DE': '#A2B4C3',
  'C6D4E0': '#A2B4C3',
  'C7D8E4': '#9EB6C7',
  'C8D8E4': '#9FB5C6',
  'C9DAE6': '#9DB6C8',
  'CFDCE7': '#9FB4C6',
  'D3E3EF': '#98B6CD',
  'D5E3EE': '#9AB5CB',
  'D8E4EE': '#9CB5C9',
  'E7F0F7': '#E1E6EA',
  'FFFFFF': '#E8EFF7',
};


/**
 * v4.21 浅色模式文字色下限（华为 UX 2.1.4.1：正文文字与背景对比度 > 4.5:1）
 * AGC 2026-11-09 上架测试报「色彩」不通过 5 次，根因是历史上大量浅灰小字对比度连 3:1 都不到。
 * 这张表只在「浅色模式 + 作为文字/图标前景色」时生效（tc 的 kind===1），
 * 同一个色值当底色/描边用时仍保持原样 —— 否则卡片、胶囊、渐变会被整片压暗。
 * 每条都按「对白卡 / 页面底 / soft / 各领域浅底 共 24 种真实底色取最差值 ≥ 4.6」反算而来。
 */
const LIGHT_TEXT_REMAP: Record<string, string> = {
  '17A8A4': '#107270',
  '1B7F76': '#18736A',
  '1F9E9A': '#16726F',
  '2E8C77': '#267261',
  '2F7FC4': '#276AA4',
  '2FA9A3': '#146F6A',
  '3AC8C2': '#20726F',
  '3D7BA6': '#356B91',
  '4E6C86': '#4C6A83',
  '5AA7E8': '#1869AE',
  '5C7086': '#56687D',
  '5E7183': '#576879',
  '6A7F92': '#576978',
  '6E8497': '#566979',
  '6FD6BE': '#217360',
  '78899C': '#596879',
  '7C5CE0': '#6E4ADD',
  '7C8F9F': '#576977',
  '7C93A6': '#54697B',
  '7E93A6': '#51697D',
  '7E97AC': '#51697E',
  '8095A8': '#55697C',
  '8FA2B3': '#54697C',
  '8FA3B6': '#52697E',
  '93A6B6': '#52697E',
  '9BAEBD': '#52697C',
  '9BAFC0': '#50697F',
  '9DB0C1': '#516980',
  '9FB2C2': '#50697E',
  '9FE0DC': '#25716D',
  'A2B3C2': '#52697E',
  'A3B3C1': '#52697E',
  'A78BFA': '#6D3EF7',
  'A85F3F': '#975539',
  'A8B8C6': '#52697E',
  'A97C1B': '#836015',
  'A9BCCA': '#4E6A7F',
  'A9C0D2': '#4B6982',
  'B0563C': '#A14F37',
  'B06A5C': '#955548',
  'B4483C': '#AD453A',
  'B6C7D4': '#4C6A81',
  'B6C8D6': '#4A6A84',
  'B7C7D4': '#4D6A82',
  'B9C9D6': '#4C6A83',
  'B9CAD8': '#4A6A85',
  'C25E4A': '#A04732',
  'C25E8C': '#AA4071',
  'C2D0DB': '#4D6A82',
  'C3D2DE': '#496A85',
  'C6D4E0': '#496A87',
  'C7D8E4': '#426B89',
  'C89A5B': '#855F2D',
  'C8D8E4': '#3F6A89',
  'C9DAE6': '#406B8A',
  'CFDCE7': '#456A8A',
  'D2795C': '#A64C2E',
  'D3E3EF': '#366B94',
  'D4705F': '#B14230',
  'D5E3EE': '#3B6B91',
  'D8E4EE': '#3E6A8F',
  'E08A6F': '#AD4625',
  'E0B4A4': '#9E5136',
  'E7F0F7': '#4B6982',
  'F5AE8E': '#B24210',
  'F6C453': '#865F07',
};

const BORDER_MAP: Record<string, string> = {

  '000000': '#575757',
  '2C4257': '#3A5773',
  'C9EDE8': '#2E4C48',
  'D8E8F4': '#2E3F4C',
  'D9E8F4': '#2E3F4C',
  'DCE9F3': '#2E3F4C',
  'DDE9F3': '#24313F',
  'DDEBF4': '#2E414C',
  'DFF3EF': '#2E4C46',
  'E4EFF8': '#2E3F4C',
  'E4F1FA': '#2E404C',
  'E6EFF8': '#223040',
  'E6F0F8': '#223040',
  'E6F1F9': '#2E404C',
  'E9F2F9': '#2E3F4C',
  'E9F3FA': '#2E404C',
  'EAF2F9': '#24313F',
  'EBF3FA': '#2E3E4C',
  'EEF6FB': '#2E414C',
  'F6D3CB': '#4C342E',
  'F8DCD7': '#4C332E',
  'EDF4FA': '#384957',
  'F2F7FB': '#384957',
};

export function tk(dark: boolean, token: string): string {
  if (dark) {
    return DARK_MAP[token] ?? LIGHT_MAP[token] ?? token;
  }
  return LIGHT_MAP[token] ?? token;
}

/**
 * v4.21：token 版「文字/图标前景色」取值。
 * 品牌色、领域色既是底色（FAB、渐变、日历色条、进度条）又是文字色，
 * 直接改 LIGHT_MAP 会把整片底色压暗，所以文字用途走这里单独换算：
 * 浅色模式套 LIGHT_TEXT_REMAP 抬到 >= 4.6:1，深色模式与 tk() 完全一致。
 */
export function tkInk(dark: boolean, token: string): string {
  const hex: string = tk(dark, token);
  if (dark) {
    return hex;
  }
  const deep: string | undefined = LIGHT_TEXT_REMAP[hex.replace('#', '').toUpperCase()];
  return deep !== undefined ? deep : hex;
}

/**
 * v4.22：压在主色/品牌渐变等「填充」上的文字与图标 —— 一律白字。
 *
 * v4.21 曾用深墨绿 #04211F 做「亮底深字」，但那批按钮会变成黑字，观感脏。
 * v4.22 改成「填充压深 + 白字」：把 LIGHT_MAP 里的品牌色和领域色整体压到
 * 白字 >= 4.6:1（brand #3AC8C2 2.05 -> #12706B 5.91，渐变 -> #1C7C74/#1B7799
 * 5.02/5.07，其余见 LIGHT_MAP 注释），所以这里两种模式都可以直接返回白色。
 * 深色模式本来就压在 SURF_MAP 映射出的深底上，白字一直达标。
 */
export function onFill(dark: boolean): string {
  return '#FFFFFF';
}

export function tc(dark: boolean, hex: string, kind: number): string {
  const raw: string = hex.replace('#', '').toUpperCase();
  if (!dark) {
    // v4.21：浅色模式下的文字/图标前景色统一抬到合规对比度
    if (kind === 1) {
      const deep: string | undefined = LIGHT_TEXT_REMAP[raw];
      if (deep !== undefined) {
        return deep;
      }
    }
    // v4.22：浅色模式下写死的亮色底换成压深版（白字才够 4.6:1）
    if (kind === 0) {
      const sink: string | undefined = LIGHT_SURF_MAP[raw];
      if (sink !== undefined) {
        return sink;
      }
    }
    return hex;
  }
  const up: string = hex.replace('#', '').toUpperCase();
  if (kind === 0) {
    return SURF_MAP[up] ?? hex;
  }
  if (kind === 1) {
    return TEXT_MAP[up] ?? hex;
  }
  return BORDER_MAP[up] ?? hex;
}

export class C {
  // ---- 底色与层次（CSS: --bg / --card / --card2 / --line）----
  static get bg(): string { return tk(isDark(), 'bg'); };
  static get card(): string { return tk(isDark(), 'card'); };
  static get card2(): string { return tk(isDark(), 'card2'); };        // 卡内浅底块（.mod 的背景）
  static get cardBorder(): string { return tk(isDark(), 'cardBorder'); };   // 卡片 1px 描边
  static get line(): string { return tk(isDark(), 'line'); };         // 分隔线
  static get divider(): string { return tk(isDark(), 'divider'); };      // 旧名保留（图表网格线在用）
  static get soft(): string { return tk(isDark(), 'soft'); };
  static get track(): string { return tk(isDark(), 'track'); };        // 进度条底色

  // ---- 文字（--ink / --muted / --dim）----
  static get text(): string { return tk(isDark(), 'text'); };
  static get textSub(): string { return tk(isDark(), 'textSub'); };
  static get textFaint(): string { return tk(isDark(), 'textFaint'); };    // --dim
  static get textHint(): string { return tk(isDark(), 'textHint'); };     // 卡片小字（.sub / .meta）
  static get textPale(): string { return tk(isDark(), 'textPale'); };     // 空态文字

  // ---- 主色（--acc / --acc-d / --acc-soft / --acc-line）----
  static get brand(): string { return tk(isDark(), 'brand'); };
  static get brandDeep(): string { return tk(isDark(), 'brandDeep'); };
  static get brandSoft(): string { return tk(isDark(), 'brandSoft'); };
  static get brandLine(): string { return tk(isDark(), 'brandLine'); };
  static get gradFrom(): string { return tk(isDark(), 'gradFrom'); };
  static get gradTo(): string { return tk(isDark(), 'gradTo'); };
  static get brandTint(): string { return tk(isDark(), 'brandTint'); };

  // ---- 领域色（--blue / --lav / --peach / --mint / --amber）----
  static get work(): string { return tk(isDark(), 'work'); };         // 工作
  static get side(): string { return tk(isDark(), 'side'); };         // 副业
  static get media(): string { return tk(isDark(), 'media'); };        // 自媒体（peach，不是粉）
  static get study(): string { return tk(isDark(), 'study'); };        // 学习
  static get life(): string { return tk(isDark(), 'life'); };         // 生活
  static get event(): string { return tk(isDark(), 'event'); };        // 日程（sky）

  // ---- 语义 ----
  static get danger(): string { return tk(isDark(), 'danger'); };       // .late 圆点
  static get dangerSoft(): string { return tk(isDark(), 'dangerSoft'); };
  static get done(): string { return tk(isDark(), 'done'); };
  static get doing(): string { return tk(isDark(), 'doing'); };
  static get todo(): string { return tk(isDark(), 'todo'); };
  static get heat0(): string { return tk(isDark(), 'heat0'); };
  static get checkRing(): string { return tk(isDark(), 'checkRing'); };    // .check 未完成的圈

  // ---- 任务状态圈圈三态（v2.8）----
  // 待办 = 白色空心圈（对齐工作台 .tcard .check）
  // 进行中 = 半色：浅琥珀底 + 琥珀边 + 中心半透明实心点
  // 已完成 = 全色：薄荷绿实心 + 白勾
  static get doingSoft(): string { return tk(isDark(), 'doingSoft'); };    // 进行中圈底（浅琥珀）
  static get doingLine(): string { return tk(isDark(), 'doingLine'); };    // 进行中圈边
  static get doneDeep(): string { return tk(isDark(), 'doneDeep'); };     // 已完成圈上的勾（深青白）
}

/** 尺寸：卡片 20 圆角、按钮 11、页面左右 13（手机端 main padding:16px 13px） */
export class S {
  static readonly radiusCard: number = 20;
  static readonly radiusInner: number = 13;   // .tcard / .mod / .tstat
  static readonly radiusBtn: number = 11;
  static readonly radiusPill: number = 999;
  static readonly gap: number = 12;
  static readonly gapLg: number = 14;         // .home-grid gap
  static readonly padCard: number = 0;        // 用 headPad/bodyPad 分区，见 Card
  static readonly headPadH: number = 14;      // .c-head padding: 13px 14px 0
  static readonly headPadT: number = 13;
  static readonly bodyPadH: number = 14;      // .c-body padding: 10px 14px 14px
  static readonly bodyPadT: number = 10;
  static readonly bodyPadB: number = 14;
  static readonly pagePad: number = 13;       // main padding 左右
  static readonly pageTop: number = 16;
  static readonly pageBottom: number = 92;    // 给底部导航留白
  static readonly tabBarH: number = 52;       // 工作台手机端是 17px 图标 + 9px 文字的小标签

  // ---- 字号（手机端断点后的实际值）----
  static readonly titleSize: number = 25;     // h1（手机端 25px）
  static readonly cardTitleSize: number = 14; // .c-head h2
  static readonly bodySize: number = 12.5;    // .tt
  static readonly subSize: number = 10.5;     // 次要说明
  static readonly tinySize: number = 9.5;     // .meta / .kpi-top
  static readonly microSize: number = 8.5;    // .cat / .w-foot
  static readonly numberSize: number = 22;    // .kpi b（手机端 22px）
  static readonly bigNumber: number = 26;
}

/** 领域色的「标签」配色（工作台 catStyle：浅底 + 深字） */
export function catBg(dark: boolean, area: string): string {
  switch (area) {
    case 'work': return dark ? '#16273A' : '#E8F2FC';
    case 'side': return dark ? '#241E3A' : '#F1ECFE';
    case 'media': return dark ? '#331F2A' : '#FCEAF2';
    case 'study': return dark ? '#14302C' : '#E3F8F2';
    case 'life': return dark ? '#33291A' : '#FDF4DC';
    default: return dark ? '#16273A' : '#E8F2FC';
  }
}

export function catColor(dark: boolean, area: string): string {
  switch (area) {
    // v4.21：浅色这组是压在同色浅底（catBg）上的标签字，全部重算到 >=4.55:1
    case 'work': return dark ? '#7FB6F0' : '#2970AD';
    case 'side': return dark ? '#B79BFB' : '#7355D0';
    case 'media': return dark ? '#F49AC1' : '#A44F77';
    case 'study': return dark ? '#6FD6BE' : '#287B68';
    case 'life': return dark ? '#FFD066' : '#8F6916';
    default: return dark ? '#7FB6F0' : '#2970AD';
  }
}

/** 领域色（圆点 / 描边 / 甘特块用） */
export function areaColor(dark: boolean, area: string): string {
  switch (area) {
    case 'work': return tk(dark, 'work');
    case 'side': return tk(dark, 'side');
    case 'media': return tk(dark, 'media');
    case 'study': return tk(dark, 'study');
    case 'life': return tk(dark, 'life');
    default: return tk(dark, 'work');
  }
}

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

/** 甘特色块（.bar.lav / .mint / .peach / .sky）的底色与字色 */
export function barBg(dark: boolean, area: string): string {
  switch (area) {
    case 'side': return dark ? '#241E3A' : '#EFE9FE';
    case 'study': return dark ? '#14302C' : '#DFF6EF';
    case 'media': return dark ? '#33211C' : '#FDE9DF';
    default: return dark ? '#16273A' : '#E4F1FB';
  }
}

export function barColor(dark: boolean, area: string): string {
  switch (area) {
    // v4.21：压在同色浅底（barBg）上的甘特块字色，同样重算到 >=4.55:1
    case 'side': return dark ? '#B79BFB' : '#6B4FD0';
    case 'study': return dark ? '#6FD6BE' : '#287A68';
    case 'media': return dark ? '#E0A88A' : '#9D593B';
    default: return dark ? '#7FB6F0' : '#387199';
  }
}

export function statusLabel(s: string): string {
  switch (s) {
    case 'todo': return '待办';
    case 'doing': return '进行中';
    case 'done': return '完成';
    default: return s;
  }
}

export function statusColor(dark: boolean, s: string): string {
  switch (s) {
    case 'todo': return tk(dark, 'todo');
    case 'doing': return tk(dark, 'doing');
    case 'done': return tk(dark, 'brand');
    default: return tk(dark, 'textHint');
  }
}

export function priorityLabel(p: string): string {
  switch (p) {
    case 'high': return '要紧';
    case 'med': return '普通';
    case 'low': return '随手';
    default: return '普通';
  }
}

export function priorityColor(dark: boolean, p: string): string {
  switch (p) {
    case 'high': return dark ? '#F0A288' : '#D2795C';
    case 'med': return tk(dark, 'textFaint');
    case 'low': return tk(dark, 'textHint');
    default: return tk(dark, 'textHint');
  }
}

/** 工作台的统一卡片阴影 --sh: 0 10px 30px rgba(37,84,133,.07) */
export function cardShadow(dark: boolean): ShadowOptions {
  return dark
    ? { radius: 30, color: 'rgba(0,0,0,0.35)', offsetX: 0, offsetY: 10 }
    : { radius: 30, color: 'rgba(37,84,133,0.07)', offsetX: 0, offsetY: 10 };
}

/** 浮层（弹窗/抽屉）的深阴影 --sh-lg 变体 */
export function sheetShadow(dark: boolean): ShadowOptions {
  return dark
    ? { radius: 50, color: 'rgba(0,0,0,0.55)', offsetX: 0, offsetY: 12 }
    : { radius: 50, color: 'rgba(37,84,133,0.18)', offsetX: 0, offsetY: 12 };
}

/** 主色渐变（.primary / .mc-day.today 都用 140deg） */
export function brandGradient(): LinearGradient {
  return { angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] };
}

/** 主色渐变的浅色版（进度条 i：linear-gradient(90deg,#5AD7C9,#3AC8C2)） */
export function trackGradient(): LinearGradient {
  return { angle: 90, colors: [['#12706B', 0], ['#0F6B66', 1]] };
}
