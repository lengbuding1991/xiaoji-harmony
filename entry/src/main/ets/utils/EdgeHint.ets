/*
 * EdgeHint · 滑动到边界时的反馈（v4.24 新增）
 *
 * 背景（为什么以前完全没有反馈）：
 *   Scroll 的 edgeEffect 默认值是 EdgeEffect.None —— SDK common.d.ts:25291 写明
 *   「Default value: EdgeEffect.None for the Grid, Scroll, and WaterFlow components
 *     and EdgeEffect.Spring for the List component」。
 *   也就是说：只有 List 默认带回弹，Scroll 默认是硬停；再加上我们工程里只有 Scroll、
 *   没有 List，所以手指滑到顶或底时一点反馈都没有 —— 这就是用户说的「滑到边界没反馈」。
 *
 * 这一层做两件事：
 *   1) 真正的物理反馈：给每个 Scroll 补 .edgeEffect(EdgeEffect.Spring)。
 *      内容被拉出边界时会被「拉住」，松手回弹。（v4.24 已给 6 处漏掉的 Scroll 补齐。）
 *   2) 明确的视觉反馈：用户真的把内容拉出边界时，在靠近那条边的位置弹一个小提示胶囊。
 *
 * 怎么判断「真的拉出边界」：
 *   onScrollEdge 在「滚到边缘」时就触发（普通上滑到顶也会），不能拿它当越界信号；
 *   onWillScroll 的 scrollSource === ScrollSource.EDGE_EFFECT 才是「越界回弹」这一段
 *   （SDK enums.d.ts 里 EDGE_EFFECT 的注释原文就是 "Over scroll with EdgeEffect.Spring."）。
 *
 * 横向也留了口子：Edge 只有 Top/Bottom（纵向）和 Start/End（横向），没有 Left/Right。
 * 将来加横向 Scroll 时，同一行 edgeEffect 就自动覆盖左右两个方向。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

/* ---------- AppStorage 键（@StorageLink 要求 key 先存在，EntryAbility 里已初始化） ---------- */
export const EDGE_TEXT_KEY: string = 'wb_edge_hint_text';
export const EDGE_SIDE_KEY: string = 'wb_edge_hint_side';
export const EDGE_SEQ_KEY: string = 'wb_edge_hint_seq';

/* ---------- 四个方向 ---------- */
export const EDGE_TOP: number = 0;
export const EDGE_BOTTOM: number = 1;
export const EDGE_START: number = 2;
export const EDGE_END: number = 3;

/** onScrollEdge 报上来的最近一条边 */
let lastSide: number = EDGE_TOP;
/** 上一次弹提示的时刻：一次回弹会连着报很多帧，压成一次 */
let lastShownAt: number = 0;

export function edgeSideCode(side: Edge): number {
  if (side === Edge.Bottom) {
    return EDGE_BOTTOM;
  }
  if (side === Edge.Start) {
    return EDGE_START;
  }
  if (side === Edge.End) {
    return EDGE_END;
  }
  return EDGE_TOP;
}

/** Scroll.onScrollEdge 的回调：只记方向，不弹提示（普通滚到边缘也会触发） */
export function onEdgeScrolled(side: Edge): void {
  lastSide = edgeSideCode(side);
}

/** Scroll.onWillScroll 的回调：只有越界回弹这一段才弹提示 */
export function onEdgeWillScroll(xOffset: number, yOffset: number, scrollState: ScrollState, scrollSource: ScrollSource): void {
  if (scrollSource !== ScrollSource.EDGE_EFFECT) {
    return;
  }
  showEdgeHint();
  hilog.debug(DOMAIN, 'workbench', 'edge overscroll x=%{public}d y=%{public}d state=%{public}d', xOffset, yOffset, scrollState);
}

function edgeHintText(side: number): string {
  if (side === EDGE_BOTTOM) {
    return '已经到底了';
  }
  if (side === EDGE_START) {
    return '已经到最左边了';
  }
  if (side === EDGE_END) {
    return '已经到最右边了';
  }
  return '已经到顶了';
}

/** 弹一次边界提示（700ms 内重复调用只算一次） */
export function showEdgeHint(): void {
  const now: number = Date.now();
  if (now - lastShownAt < 700) {
    return;
  }
  lastShownAt = now;
  AppStorage.setOrCreate<string>(EDGE_TEXT_KEY, edgeHintText(lastSide));
  AppStorage.setOrCreate<number>(EDGE_SIDE_KEY, lastSide);
  AppStorage.setOrCreate<number>(EDGE_SEQ_KEY, now);
}
