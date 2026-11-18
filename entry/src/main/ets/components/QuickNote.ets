// 快速记录（对齐「个人工作台」components/QuickCapture.tsx + globals.css .qc）
//   居中卡片：标题「快速记一笔」+「写完点右下角『记下』」+ 右上关闭圆按钮
//   textarea「想到什么，先扔进来。不用整理，不用分类。」
//   底部一行：四个来源胶囊 + 最右「记下」按钮（没有「取消」按钮、没有字数）
//   保存走 POST /api/notes，body { title: 首行前 40 字, content, source }
import { Repo } from '../db/Repo';
import { brandGradient, onFill, S, sheetShadow, tc, tk, tkInk } from '../utils/Theme';
import { toast } from '../utils/Toast';
import { sym } from './Icon';
import { NoteCreate } from '../api/Types';
import { Store } from '../store/Store';

const TAGS: string[] = ['灵感', '工作', '学习', '复盘'];

@Component
export struct QuickNote {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @State text: string = '';
  @State tag: string = '灵感';
  @State busy: boolean = false;
  @State err: string = '';
  onDone: () => void = () => {};

  private firstLine(): string {
    const idx: number = this.text.indexOf('\n');
    const line: string = idx > 0 ? this.text.substring(0, idx) : this.text;
    return line.trim().substring(0, 40);
  }

  private async save(): Promise<void> {
    const body0: string = this.text.trim();
    if (body0.length === 0) {
      this.err = '先写一句再记';
      return;
    }
    this.busy = true;
    this.err = '';
    const body: NoteCreate = {
      title: this.firstLine(),
      content: this.text,
      source: this.tag
    } as NoteCreate;
    try {
      await Repo.createNote(body);
      await Store.I.reloadNotes();
      this.busy = false;
      toast(this.getUIContext(), '已记下，存在「随手记」里');
      this.text = '';
      this.onDone();
    } catch (e) {
      this.busy = false;
      this.err = (e as Error).message;
    }
  }

  build() {
    Column() {
      // .qc-head: 标题 + 右上提示 + 关闭圆按钮
      Row({  space: S.spaceLg  }) {
        SymbolGlyph(sym('pen')).fontSize(S.midSize).fontColor([tkInk(this.pal, 'brandDeep')])
        Text('快速记一笔').fontSize(S.cardTitleSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text'))
        // v5.13：原来写「写完按 ⌘↵ 保存」—— 手机上没有 ⌘ 键，这条提示等于没有。
        //   改成指向屏幕上真实存在的按钮。
        Text('写完点右下角「记下」').fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint'))
        Blank()
        // v5.15 可访问性：关闭按钮原来只有 25×25 ⇒ 外层套 40×40 的透明热区，
        //   里层 25×25 的灰底圆角块保持原样（视觉不变）。
        Row() {
          Row() {
            SymbolGlyph(sym('close')).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#8FA2B3', 1)])
          }
          .width(25).height(25).borderRadius(S.radiusSm)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .backgroundColor(tc(this.pal, '#F2F7FB', 0))
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.onDone(); })
        .accessibilityText('关闭')
      }
      .width('100%')
      .margin({  bottom: S.spaceXl  })
      .alignItems(VerticalAlign.Center)

      TextArea({ placeholder: '想到什么，先扔进来。不用整理，不用分类。', text: this.text })
        .fontSize(S.midSize)
        .placeholderFont({ size: 13 })
        .placeholderColor(tc(this.pal, '#A8B8C6', 1))
        .fontColor(tk(this.pal, 'text'))
        .caretColor(tk(this.pal, 'brand'))
        .constraintSize({ minHeight: 130 })
        .width('100%')
        .backgroundColor(tc(this.pal, '#F8FBFE', 0))
        .borderRadius(S.radiusInner)
        .border({ width: 1, color: tk(this.pal, 'line') })
        .padding({  left: S.space3Xl, right: S.space3Xl, top: S.space2Xl, bottom: S.space2Xl  })
        .onChange((v: string) => { this.text = v; })

      if (this.err.length > 0) {
        Text(this.err)
          // v5.15 可访问性：保存失败提示原来 11px ⇒ 字号 ≥12（S.smallSize）+ danger 色
          .fontSize(S.smallSize).fontColor(tkInk(this.pal, 'danger'))
          .width('100%').padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceLg, bottom: S.spaceLg  })
          .borderRadius(S.radiusBtn).backgroundColor(tk(this.pal, 'dangerSoft'))
          .border({ width: 1, color: tk(this.pal, 'dangerSoft') })
          .margin({  top: S.spaceXl  })
      }

      // .tags: 四个来源胶囊 + 最右「记下」（没有取消按钮）
      Row({  space: S.spaceMd  }) {
        ForEach(TAGS, (t: string) => {
          // v5.15 可访问性：来源胶囊原来只有 22 高 ⇒ 外层套 40 高的透明热区，
          //   里层胶囊保持原来的样子（视觉不变）。
          Row() {
            Text(t)
              .fontSize(S.subSize)
              .fontColor(this.tag === t ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#6A7F92', 1))
              .fontWeight(this.tag === t ? FontWeight.Medium : FontWeight.Normal)
              .padding({  left: S.space2Xl, right: S.space2Xl, top: S.spaceMd, bottom: S.spaceMd  })
              .borderRadius(S.radiusPill)
              .backgroundColor(this.tag === t ? tk(this.pal, 'brandSoft') : tc(this.pal, '#FFFFFF', 0))
              .border({ width: 1, color: this.tag === t ? tk(this.pal, 'brandLine') : tk(this.pal, 'line') })
          }
          .height(40)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .onClick(() => { this.tag = t; })
          .accessibilityText(`来源 ${t}`)
        }, (t: string) => `qc-${t}`)
        Blank()
        Text(this.busy ? '保存中…' : '记下')
          .fontSize(S.smallSize).fontColor(onFill(this.pal)).fontWeight(FontWeight.Medium)
          // v5.15 可访问性：「记下」按钮高 34 → 40
          .height(40).padding({  left: S.space4Xl, right: S.space4Xl  })
          .borderRadius(S.radiusBtn).textAlign(TextAlign.Center)
          .linearGradient(brandGradient(this.pal))
          .opacity(this.busy ? 0.6 : 1)
          .onClick(() => { if (!this.busy) { this.save(); } })
          .accessibilityText('记下')
      }
      .width('100%')
      .margin({  top: S.spaceXl  })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(18)
    .borderRadius(S.radiusCard)
    .border({ width: 1, color: tk(this.pal, 'line') })
    .backgroundColor(tc(this.pal, '#FFFFFF', 0))
    .shadow(sheetShadow(this.pal))
  }
}
