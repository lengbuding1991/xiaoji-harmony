// 环形图：对齐工作台 .donut（132×132，conic-gradient + inset:26px 白心）
// 用 sweepGradient 实现 conic-gradient，比 Canvas 更接近原版并且没有重绘开销。
import { C, tk, tc } from '../utils/Theme';

export interface RingPiece {
  label: string;
  value: number;
  color: string;
  pct: number;
}

export function ringPiece(label: string, value: number, color: string, pct: number): RingPiece {
  return { label: label, value: value, color: color, pct: pct };
}

@Component
export struct Donut {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop pieces: RingPiece[] = [];
  @Prop boxSize: number = 132;
  @Prop holeSize: number = 26;
  /** 中间大字（工作台 .donut .mid b） */
  @Prop centerBig: string = '';
  @Prop centerSmall: string = '';

  private colors(): Array<[ResourceColor, number]> {
    const list: Array<[ResourceColor, number]> = [];
    if (this.pieces.length === 0) {
      list.push([tk(this.dark, 'heat0'), 0]);
      list.push([tk(this.dark, 'heat0'), 1]);
      return list;
    }
    let acc: number = 0;
    for (let i = 0; i < this.pieces.length; i++) {
      const p = this.pieces[i];
      const span: number = p.pct / 100;
      list.push([p.color, acc]);
      acc += span;
      list.push([p.color, acc]);
    }
    // 收尾对齐到 1，避免浮点误差留下细缝
    list.push([this.pieces[this.pieces.length - 1].color, 1]);
    return list;
  }

  build() {
    Stack() {
      Row()
        .width(this.boxSize)
        .height(this.boxSize)
        .borderRadius(this.boxSize / 2)
        .sweepGradient({ center: [this.boxSize / 2, this.boxSize / 2], colors: this.colors() })

      Row()
        .width(this.boxSize - this.holeSize * 2)
        .height(this.boxSize - this.holeSize * 2)
        .borderRadius((this.boxSize - this.holeSize * 2) / 2)
        .backgroundColor(tk(this.dark, 'card'))

      if (this.centerBig.length > 0) {
        Column({ space: 1 }) {
          Text(this.centerBig)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(tk(this.dark, 'text'))
          if (this.centerSmall.length > 0) {
            Text(this.centerSmall).fontSize(8).fontColor(tk(this.dark, 'textHint'))
          }
        }
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width(this.boxSize)
    .height(this.boxSize)
  }
}

/** 图例（.legend）：色点 + 名称 + 右对齐百分比 */
@Component
export struct DonutLegend {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop pieces: RingPiece[] = [];

  build() {
    Column({ space: 6 }) {
      ForEach(this.pieces, (p: RingPiece) => {
        Row({ space: 7 }) {
          Row().width(7).height(7).borderRadius(4).backgroundColor(p.color)
          Text(p.label).fontSize(S_LABEL).fontColor(tc(this.dark, '#5E7183', 1))
          Blank()
          Text(`${p.pct}%`).fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (p: RingPiece) => p.label)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

const S_LABEL: number = 10.5;
