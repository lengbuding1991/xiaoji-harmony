// 折线图（Canvas 自绘，不引第三方库）
// 对齐工作台 .trend svg：三条网格线、面积渐变 0.26→0、圆点白心青边、末点数值气泡、底部 M/d 轴标。
//
// v4.3 修正（真机量出来的）：**Canvas 上下文的坐标系是 vp**，不是 px。
// 真机日志：`ctx.width = 320.57`、`ctx.height = 150`（= chartHeight 的 vp 值）⇒ 画布坐标系就是 vp。
// 于是有两条坑：
//  1) `ctx.font` 必须是**完整简写**（字号 + 字体族），而里面的 `px` 是**设备像素**——
//     之前写的 `'12.5fp'` 既没有字体族、单位也不合法 ⇒ 整条赋值被忽略，
//     字号退回默认 `'normal normal 14px sans-serif'`，在 vp 坐标系里只有 14/3.5 ≈ 4vp ⇒ 字小得看不清。
//     现在字号用 **`vp`** 单位写（`'11vp sans-serif'`），才是真正的 11vp。
//  2) 画布坐标系既然是 vp，线宽、圆点半径、留白就都按 vp 直接写，不要再乘密度。
import { C, onFill, tc, tk } from '../utils/Theme';

@Component
export struct LineChart {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') @Watch('onDarkChanged') dark: boolean = false;
  @Prop values: number[] = [];
  @Prop labels: string[] = [];
  @Prop chartHeight: number = 150;
  @Prop showBubble: boolean = true;
  // v4.5：把末点气泡在画布里的位置报出去（首页用它判断会不会被右下角悬浮按钮压住）
  onBubble: (x: number, y: number, w: number, h: number) => void = () => {};
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(this.chartHeight)
      .onReady(() => { this.draw(); })
  }

  /** v4.8：主题切换后画布不会自动重画，这里手动重画一次 */
  private onDarkChanged(): void {
    this.draw();
  }

  private draw(): void {
    const ctx = this.ctx;
    // 画布坐标系 = vp（真机实测 ctx.width=320.57 / ctx.height=150）
    const w: number = ctx.width > 0 ? ctx.width : 320;
    const h: number = ctx.height > 0 ? ctx.height : this.chartHeight;
    ctx.clearRect(0, 0, w, h);
    const n = this.values.length;
    if (n === 0) { return; }

    let max = 0;
    for (let i = 0; i < n; i++) { if (this.values[i] > max) { max = this.values[i]; } }
    // 工作台：trendTop = max(v * 1.45)，最低 1
    const top: number = Math.max(1, Math.round(max * 1.45 * 10) / 10);

    const padX = 16;      // 左右留白
    const padT = 30;      // 顶部给气泡留位置
    const padB = 30;      // 底部给轴标留位置
    const gw = w - padX * 2;
    const gh = h - padT - padB;

    const xOf = (i: number): number => (n === 1 ? padX + gw / 2 : padX + gw * i / (n - 1));
    const yOf = (i: number): number => padT + gh - gh * this.values[i] / top;

    // 网格线（三条：#EDF4FA）
    ctx.strokeStyle = tc(this.dark, '#EDF4FA', 2);
    ctx.lineWidth = 1;
    for (let g = 0; g <= 2; g++) {
      const y = padT + gh * g / 2;
      ctx.beginPath();
      ctx.moveTo(padX, y);
      ctx.lineTo(w - padX, y);
      ctx.stroke();
    }

    // 面积渐变
    const grad = ctx.createLinearGradient(0, padT, 0, padT + gh);
    grad.addColorStop(0, 'rgba(58,200,194,0.26)');
    grad.addColorStop(1, 'rgba(58,200,194,0)');
    ctx.beginPath();
    ctx.moveTo(xOf(0), padT + gh);
    for (let i = 0; i < n; i++) { ctx.lineTo(xOf(i), yOf(i)); }
    ctx.lineTo(xOf(n - 1), padT + gh);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    // 折线
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      if (i === 0) { ctx.moveTo(xOf(i), yOf(i)); } else { ctx.lineTo(xOf(i), yOf(i)); }
    }
    ctx.strokeStyle = tk(this.dark, 'brand');
    ctx.lineWidth = 2.2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke();

    // 圆点：白心 + 青边（末点稍大）
    for (let i = 0; i < n; i++) {
      ctx.beginPath();
      ctx.arc(xOf(i), yOf(i), i === n - 1 ? 5 : 4, 0, Math.PI * 2);
      ctx.fillStyle = tk(this.dark, 'card');
      ctx.fill();
      ctx.strokeStyle = tk(this.dark, 'brand');
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // 轴标 M/d（完整字体简写：字号 + 字体族；字号单位用 vp）
    ctx.font = '11vp sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = '#7E97AC';
    if (this.labels.length === n) {
      for (let i = 0; i < n; i++) {
        ctx.fillText(this.labels[i], xOf(i), h - 13);
      }
    }

    // 末点气泡：青色圆角块 + 白字
    if (this.showBubble && n > 0) {
      const text = `${this.values[n - 1]}`;
      const bw = text.length > 3 ? 58 : 46;
      const bh = 28;
      const rr = 13;
      // 气泡默认正对末点（水平居中、点在气泡正下方）。
      // 末点贴着右边时**只做最小平移**把它拉回画布内，不能整块甩到点的左边去
      // —— 那样气泡会飘在半空，看着跟末点没关系。
      let bx = xOf(n - 1);
      if (bx + bw / 2 > w - 4) { bx = w - 4 - bw / 2; }
      if (bx - bw / 2 < 4) { bx = 4 + bw / 2; }
      const by = Math.max(8, yOf(n - 1) - 12 - bh);
      this.onBubble(bx - bw / 2, by, bw, bh);
      ctx.fillStyle = tk(this.dark, 'brand');
      ctx.beginPath();
      // 圆角矩形（Canvas 没有 roundRect，手画）
      ctx.moveTo(bx - bw / 2 + rr, by);
      ctx.lineTo(bx + bw / 2 - rr, by);
      ctx.arcTo(bx + bw / 2, by, bx + bw / 2, by + rr, rr);
      ctx.lineTo(bx + bw / 2, by + bh - rr);
      ctx.arcTo(bx + bw / 2, by + bh, bx + bw / 2 - rr, by + bh, rr);
      ctx.lineTo(bx - bw / 2 + rr, by + bh);
      ctx.arcTo(bx - bw / 2, by + bh, bx - bw / 2, by + bh - rr, rr);
      ctx.lineTo(bx - bw / 2, by + rr);
      ctx.arcTo(bx - bw / 2, by, bx - bw / 2 + rr, by, rr);
      ctx.closePath();
      ctx.fill();
      // v4.21：气泡底是品牌色（#3AC8C2），白字只有 2.05:1；改成深墨绿后 8.2:1
      ctx.fillStyle = onFill(this.dark);
      ctx.font = 'bold 14vp sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(text, bx, by + bh / 2);
    }
  }
}
