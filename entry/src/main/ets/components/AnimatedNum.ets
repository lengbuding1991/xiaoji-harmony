// v5.0：数字滚动（首页 KPI 的数字从旧值「数」到新值）
//
// 为什么自己写而不用 animateTo：
//   animateTo 只能插值「属性」（opacity / scale / width …），
//   Text 里的字符串它插不了 —— 数字要一格一格变，只能自己逐帧写值。
//
// ⚠️ ArkUI V1 的老坑（v4.5 踩过，忘了又要踩）：
//   只有「属性表达式里直接读过 state」的节点才会重画。
//   所以 build() 里必须是 Text(this.shownText) —— 直接读 @State。
//   如果写成 Text(this.fmt()) 这种「方法里读 state」，数字永远不会变。
//   ⇒ 这里把格式化结果也存成 @State shownText，每一帧直接改它。
//
// 时长与曲线：420ms + easeOutCubic（快起慢停），最后一步强制对齐目标值，
// 避免浮点误差留下 2.999999 这种尾巴。
import { S, tk } from '../utils/Theme';

@Component
export struct AnimatedNum {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  // 目标值。父组件改它就触发一次滚动。
  @Prop @Watch('onValueChanged') value: number = 0;
  // 小数位（0 = 整数）
  @Prop decimals: number = 0;
  // 滚动时长（毫秒）
  @Prop duration: number = 420;
  // 当前显示值（格式化后的字符串）
  @State shownText: string = '0';

  private timer: number = -1;
  private from: number = 0;
  private to: number = 0;
  private startedAt: number = 0;

  aboutToAppear(): void {
    // 首帧直接显示目标值：不要「从 0 数上来」那种假动画
    this.from = this.value;
    this.to = this.value;
    this.shownText = this.fmt(this.value);
  }

  aboutToDisappear(): void {
    this.stop();
  }

  onValueChanged(): void {
    this.run();
  }

  private fmt(v: number): string {
    if (this.decimals <= 0) {
      return `${Math.round(v)}`;
    }
    return v.toFixed(this.decimals);
  }

  private stop(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private run(): void {
    this.stop();
    this.from = this.value === this.to && this.shownText.length > 0 ? this.readShown() : this.readShown();
    this.to = this.value;
    if (this.from === this.to) {
      this.shownText = this.fmt(this.to);
      return;
    }
    this.startedAt = Date.now();
    this.timer = setInterval(() => {
      const p: number = Math.min(1, (Date.now() - this.startedAt) / this.duration);
      const e: number = 1 - Math.pow(1 - p, 3);
      const v: number = this.from + (this.to - this.from) * e;
      this.shownText = p >= 1 ? this.fmt(this.to) : this.fmt(v);
      if (p >= 1) {
        this.shownText = this.fmt(this.to);
        this.stop();
      }
    }, 16);
  }

  // 从当前显示串里还原数字（用于下一次滚动的起点）
  private readShown(): number {
    const n: number = parseFloat(this.shownText);
    return isNaN(n) ? 0 : n;
  }

  build() {
    // ⚠️ 必须直接读 @State（shownText），不能调方法
    Text(this.shownText)
      .fontSize(S.numberSize)
      .fontWeight(FontWeight.Bold)
      .fontColor(tk(this.pal, 'text'))
  }
}
