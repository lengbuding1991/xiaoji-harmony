/**
 * FormKit —— 对齐个人工作台 app/globals.css 里 .sheet / .form / .seg / .acts 的一套表单积木。
 *
 * 关键量值（手机端 @media max-width:640px）：
 *   .sheet h3        17px / 700 / color #1D2A38
 *   .sheet .sub      9.5px / #A8B8C6 / margin-bottom 16
 *   .form label      9.5px / #8FA2B3，grid gap 5
 *   .form input      bg #F8FBFE, border 1px #E6EFF8, radius 11, padding 9/11, fontSize 12
 *   .two             grid 2 列 gap 9（手机端 1 列）
 *   .seg             gap 6；.seg-btn 11px / radius 9 / padding 6 0
 *   .acts            border-top 1px #E6EFF8 + b1 主按钮 14px radius 12 / b2 次要 13px radius 12
 *   .form-err        #B4483C on #FDF0EE, border #F8DCD7, radius 10
 */
import { brandGradient, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from './Icon';

/** 抽屉/弹窗标题块：h3 17px 粗体 + 9.5px 灰色副标题 + 可选右上「×」关闭按钮 */
@Component
export struct SheetHead {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop title: string = '';
  @Prop sub: string = '';
  @Prop showClose: boolean = false;
  onClose: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({  space: S.spaceSm  }) {
        Text(this.title)
          .fontSize(S.sectionSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(tk(this.pal, 'text'))
        if (this.sub.length > 0) {
          Text(this.sub)
            .fontSize(S.tinySize)
            .fontColor(tk(this.pal, 'textHint'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({  right: this.showClose ? 40 : 0, bottom: S.spaceSm  })

      if (this.showClose) {
        // v5.15 可访问性：关闭按钮原来只有 28×28 ⇒ 外层套 40×40 的透明热区，
        //   里层那个 28×28 的灰底圆角块保持原样（视觉不变）。
        Row() {
          Row() {
            SymbolGlyph(sym('close')).fontSize(S.midSize).fontColor([tc(this.pal, '#8FA2B3', 1)])
          }
          .width(28).height(28).borderRadius(S.radiusInner)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .backgroundColor(tc(this.pal, '#F2F7FB', 0))
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.onClose(); })
        .accessibilityText('关闭')
      }
    }
    .width('100%')
  }
}

/** 表单字段标签（9.5px #8FA2B3）+ 内容槽（只能有一个 @BuilderParam） */
@Component
export struct FormBox {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop label: string = '';
  // 标签小图标（对齐工作台 .lf-label：重复用 Repeat、提醒用 Bell，图标 11px 跟文字同一行）
  @Prop icon: string = '';
  @BuilderParam content: () => void = this.none;

  @Builder
  none() {
  }

  build() {
    Column({  space: S.spaceMd  }) {
      if (this.label.length > 0) {
        Row({  space: S.spaceSm  }) {
          if (this.icon.length > 0) {
            SymbolGlyph(sym(this.icon)).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#8FA2B3', 1)])
          }
          Text(this.label)
            .fontSize(S.tinySize)
            .fontColor(tc(this.pal, '#8FA2B3', 1))
        }
        .alignItems(VerticalAlign.Center)
      }
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 三段/多段切换（.seg），用于任务状态 */
@Component
export struct SegTabs {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop options: string[] = [];
  @Prop sel: number = 0;
  onPick: (i: number) => void = () => {
  };

  build() {
    Row({  space: S.spaceMd  }) {
      ForEach(this.options, (o: string, i: number) => {
        Text(o)
          .fontSize(S.smallSize)
          .layoutWeight(1)
          // v5.15 可访问性：分段按钮高 32 → 40（手指最小可点区域）
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(S.radiusSm)
          .backgroundColor(i === this.sel ? tk(this.pal, 'brandSoft') : tc(this.pal, '#F8FBFE', 0))
          .border({ width: 1, color: i === this.sel ? tk(this.pal, 'brandLine') : tk(this.pal, 'line') })
          .fontColor(i === this.sel ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#7E93A6', 1))
          .fontWeight(i === this.sel ? FontWeight.Medium : FontWeight.Normal)
          .onClick(() => {
            this.onPick(i);
          })
      }, (o: string, i: number) => `${o}_${i}`)
    }
    .width('100%')
  }
}

/**
 * 假下拉：外观与 .form select 一致（bg #F8FBFE / border #E6EFF8 / radius 11 / 高 36），
 * 点击弹出原生菜单。对应工作台的 <select>。
 */
@Component
export struct PickerBox {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop text: string = '';
  @Prop muted: boolean = false;
  @Prop options: string[] = [];
  onPick: (i: number) => void = () => {
  };

  /**
   * 原生 MenuElement 菜单项用系统默认 16fp（MenuAttribute.font 文档写明默认 size:16），
   * 和表单里 12fp 的字放一起特别突兀。改成自绘 Menu + MenuItem，
   * 用 Menu.font({size:12}) 把菜单里所有文字统一到 12fp、指定字色。
   */
  @Builder
  menuBuilder() {
    Menu() {
      ForEach(this.options, (o: string, i: number) => {
        MenuItem({ content: o })
          .onClick(() => {
            this.onPick(i);
          })
      }, (o: string, i: number) => `pk-${o}-${i}`)
    }
    .font({ size: 12, weight: FontWeight.Normal })
    .fontColor(tk(this.pal, 'text'))
    .radius(12)
    .backgroundColor(tc(this.pal, '#FFFFFF', 0))
  }

  build() {
    Row() {
      Text(this.text)
        .fontSize(S.smallSize)
        .fontColor(this.muted ? tk(this.pal, 'textHint') : tk(this.pal, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      // v4.23：arrow_down 在 fs14 墨迹 10.7x11.7vp（盒子 14x14 >= 12vp、墨迹 >= 8vp）
      SymbolGlyph(sym('down'))
        .fontSize(S.cardTitleSize)
        .fontColor([tk(this.pal, 'textHint')])
    }
    .width('100%')
    // v5.15 可访问性：下拉框高 36 → 40（手指最小可点区域）
    .height(40)
    .padding({  left: S.space2Xl, right: S.spaceXl  })
    .backgroundColor(tc(this.pal, '#F8FBFE', 0))
    .borderRadius(S.radiusBtn)
    .border({ width: 1, color: tk(this.pal, 'line') })
    .bindMenu(this.menuBuilder(), {
      placement: Placement.Bottom
    })
  }
}

/** 日期/时间类假输入：右侧带一个日历或时钟小图标 */
@Component
export struct DateBox {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop text: string = '';
  @Prop muted: boolean = true;
  @Prop icon: string = 'calendar';
  onTap: () => void = () => {
  };

  build() {
    Row() {
      Text(this.text)
        .fontSize(S.smallSize)
        .fontColor(this.muted ? tk(this.pal, 'textHint') : tk(this.pal, 'text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph(sym(this.icon))
        .fontSize(S.cardTitleSize)
        .fontColor([tk(this.pal, 'textFaint')])
    }
    .width('100%')
    // v5.15 可访问性：日期/时间框高 36 → 40（手指最小可点区域）
    .height(40)
    .padding({  left: S.space2Xl, right: S.spaceXl  })
    .backgroundColor(tc(this.pal, '#F8FBFE', 0))
    .borderRadius(S.radiusBtn)
    .border({ width: 1, color: tk(this.pal, 'line') })
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 保存失败时的红条（.form-err），不关弹窗 */
@Component
export struct FormErr {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop msg: string = '';

  build() {
    if (this.msg.length > 0) {
      Text(this.msg)
        // v5.15 可访问性：错误提示原来 11px 灰红字 ⇒ 字号 ≥12（S.smallSize），
        //   颜色换成调色板里的 danger（深色模式下也够对比）。
        .fontSize(S.smallSize)
        .fontColor(tkInk(this.pal, 'danger'))
        .width('100%')
        .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceXl, bottom: S.spaceXl  })
        .backgroundColor(tk(this.pal, 'dangerSoft'))
        .borderRadius(S.radiusBtn)
        .border({ width: 1, color: tk(this.pal, 'dangerSoft') })
    }
  }
}

/** 小提示（.hint2） */
@Component
export struct HintLine {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(S.microSize)
      .fontColor(tk(this.pal, 'textHint'))
      .width('100%')
      .lineHeight(15)
  }
}

/** 底部动作条：主按钮渐变 14px，次按钮 13px，可选左侧危险删除 */
@Component
export struct SheetActs {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop primaryText: string = '保存';
  @Prop secondaryText: string = '取消';
  @Prop dangerText: string = '';
  @Prop busy: boolean = false;
  onPrimary: () => void = () => {
  };
  onSecondary: () => void = () => {
  };
  onDanger: () => void = () => {
  };

  build() {
    // 对齐 globals.css 手机端 .acts：删除(固定) + 取消(固定) + 保存(flex:1 撑满)
    // 没有 Blank()——它会和 layoutWeight(1) 争抢剩余空间，把按钮挤出屏幕。
    Row({  space: S.spaceLg  }) {
      if (this.dangerText.length > 0) {
        Text(this.dangerText)
          .fontSize(S.midSize)
          .fontColor(tc(this.pal, '#B0563C', 1))
          .height(44)
          .padding({  left: S.space4Xl, right: S.space4Xl  })
          .borderRadius(S.radiusInner)
          .backgroundColor(tc(this.pal, '#FEF3F0', 0))
          .border({ width: 1, color: tc(this.pal, tc(this.pal, '#F6D3CB', 2), 2) })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onDanger();
          })
      }
      Text(this.secondaryText)
        .fontSize(S.midSize)
        .fontColor(tc(this.pal, '#6A7F92', 1))
        .height(44)
        .padding({  left: S.space4Xl, right: S.space4Xl  })
        .borderRadius(S.radiusInner)
        .backgroundColor(tk(this.pal, 'card'))
        .border({ width: 1, color: tk(this.pal, 'line') })
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onSecondary();
        })
      Text(this.busy ? '保存中…' : this.primaryText)
        .fontSize(S.cardTitleSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(onFill(this.pal))
        .height(44)
        .layoutWeight(1)
        .borderRadius(S.radiusInner)
        .textAlign(TextAlign.Center)
        .linearGradient(brandGradient(this.pal))
        .opacity(this.busy ? 0.6 : 1)
        .onClick(() => {
          if (!this.busy) {
            this.onPrimary();
          }
        })
    }
    .width('100%')
    .padding({  left: S.space5Xl, right: S.space5Xl, top: S.space2Xl, bottom: S.space2Xl  })
    .border({ width: { top: 1 }, color: tk(this.pal, 'line') })
  }
}
