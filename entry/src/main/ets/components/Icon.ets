// 图标：用系统 SymbolGlyph 资源（sys.symbol.*），风格与工作台的 lucide 线性图标接近。
// 注意 $r('sys.symbol.x') 必须是字面量，所以用 switch 逐个返回，不能用变量拼字符串。
// 名称均已在 SDK 的 sysResource.js 里核对存在。

export function sym(name: string): Resource {
  switch (name) {
    case 'home': return $r('sys.symbol.house');
    case 'homeFill': return $r('sys.symbol.house_fill');
    case 'tasks': return $r('sys.symbol.list_bullet');
    case 'tasksFill': return $r('sys.symbol.list_checkmask');
    case 'calendar': return $r('sys.symbol.calendar');
    case 'calendarFill': return $r('sys.symbol.calendar_fill');
    case 'note': return $r('sys.symbol.square_and_pencil');
    case 'noteFill': return $r('sys.symbol.square_and_pencil_fill');
    case 'more': return $r('sys.symbol.square_grid_2x2');
    // v4.23：markdown 列表圆点（原来用字符「•」，墨迹只有 3.4vp）
    case 'bullet': return $r('sys.symbol.circle_fill');
    case 'moreFill': return $r('sys.symbol.square_fill_grid_2x2');
    case 'check': return $r('sys.symbol.checkmark');
    case 'checkCircle': return $r('sys.symbol.checkmark_circle');
    case 'flame': return $r('sys.symbol.flame');
    case 'clock': return $r('sys.symbol.clock');
    case 'star': return $r('sys.symbol.star');
    case 'plus': return $r('sys.symbol.plus');
    // v4.23（华为 UX 2.1.4.3.2）：chevron_* 是窄符号，fs12 时盒子只有 6.3vp 宽、
    // 墨迹只有 4.3vp 宽，放大到 fs24 也过不了 8vp 硬底线 → 换成等宽箭头。
    // arrow_right / arrow_left / arrow_down / arrow_up 在 fs16 时盒子 16x16vp、
    // 墨迹最短边 >= 12.0vp，盒子与墨迹两个口径同时达标。
    case 'left': return $r('sys.symbol.arrow_left');
    case 'right': return $r('sys.symbol.arrow_right');
    case 'down': return $r('sys.symbol.arrow_down');
    case 'up': return $r('sys.symbol.arrow_up');
    case 'gear': return $r('sys.symbol.gearshape');
    case 'search': return $r('sys.symbol.magnifyingglass');
    case 'quote': return $r('sys.symbol.quote');
    case 'bulb': return $r('sys.symbol.lightbulb');
    case 'wand': return $r('sys.symbol.wand_and_stars');
    case 'book': return $r('sys.symbol.book');
    case 'target': return $r('sys.symbol.dart_target');
    case 'person': return $r('sys.symbol.person');
    case 'trash': return $r('sys.symbol.trash');
    case 'close': return $r('sys.symbol.xmark');
    case 'bell': return $r('sys.symbol.bell');
    case 'doc': return $r('sys.symbol.doc_text');
    case 'grid': return $r('sys.symbol.dot_grid_2x2');
    case 'palette': return $r('sys.symbol.paintpalette');
    case 'folder': return $r('sys.symbol.folder');
    case 'folderFill': return $r('sys.symbol.folder_fill');
    case 'undo': return $r('sys.symbol.arrow_counterclockwise');
    case 'redo': return $r('sys.symbol.arrow_clockwise');
    case 'power': return $r('sys.symbol.power');
    case 'pin': return $r('sys.symbol.pin');
    case 'pinFill': return $r('sys.symbol.pin_fill');
    case 'archive': return $r('sys.symbol.archivebox');
    case 'archiveFill': return $r('sys.symbol.archivebox_fill');
    case 'eye': return $r('sys.symbol.eye');
    case 'pen': return $r('sys.symbol.pencil_line');
    case 'checkFill': return $r('sys.symbol.checkmark_circle_fill');
    case 'play': return $r('sys.symbol.play');
    case 'playFill': return $r('sys.symbol.play_fill');
    case 'clockFill': return $r('sys.symbol.clock_fill');
    case 'starFill': return $r('sys.symbol.star_fill');
    case 'flameFill': return $r('sys.symbol.flame_fill');
    case 'gearFill': return $r('sys.symbol.gearshape_fill');
    case 'bellFill': return $r('sys.symbol.bell_fill');
    case 'line3': return $r('sys.symbol.line_3_horizontal');
    case 'calendarBadge': return $r('sys.symbol.calendar_badge_clock');
    default: return $r('sys.symbol.circle');
  }
}
