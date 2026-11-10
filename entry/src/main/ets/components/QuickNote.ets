// 快速记录（对齐「个人工作台」components/QuickCapture.tsx + globals.css .qc）
//   居中卡片：标题「快速记一笔」+「写完按 ⌘↵ 保存」+ 右上关闭圆按钮
//   textarea「想到什么，先扔进来。不用整理，不用分类。」
//   底部一行：四个来源胶囊 + 最右「记下」按钮（没有「取消」按钮、没有字数）
//   保存走 POST /api/notes，body { title: 首行前 40 字, content, source }
import { Repo } from '../db/Repo';
import { C, onFill, tc, tk, tkInk } from '../utils/Theme';
import { toast } from '../utils/Toast';
import { sym } from './Icon';
import { NoteCreate } from '../api/Types';
import { Store } from '../store/Store';

const TAGS: string[] = ['灵感', '工作', '学习', '复盘'];

@Component
export struct QuickNote {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
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
      toast(this.getUIContext(), '已记下，存在「记录」里');
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
      Row({ space: 8 }) {
        SymbolGlyph(sym('pen')).fontSize(13).fontColor([tkInk(this.dark, 'brandDeep')])
        Text('快速记一笔').fontSize(14).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text'))
        Text('写完按 ⌘↵ 保存').fontSize(8.5).fontColor(tk(this.dark, 'textHint'))
        Blank()
        Row() {
          SymbolGlyph(sym('close')).fontSize(14).fontColor([tc(this.dark, '#8FA2B3', 1)])
        }
        .width(25).height(25).borderRadius(8)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .backgroundColor(tc(this.dark, '#F2F7FB', 0))
        .onClick(() => { this.onDone(); })
      }
      .width('100%')
      .margin({ bottom: 10 })
      .alignItems(VerticalAlign.Center)

      TextArea({ placeholder: '想到什么，先扔进来。不用整理，不用分类。', text: this.text })
        .fontSize(13)
        .placeholderFont({ size: 13 })
        .placeholderColor(tc(this.dark, '#A8B8C6', 1))
        .fontColor(tk(this.dark, 'text'))
        .caretColor(tk(this.dark, 'brand'))
        .constraintSize({ minHeight: 130 })
        .width('100%')
        .backgroundColor(tc(this.dark, '#F8FBFE', 0))
        .borderRadius(12)
        .border({ width: 1, color: tk(this.dark, 'line') })
        .padding({ left: 13, right: 13, top: 11, bottom: 11 })
        .onChange((v: string) => { this.text = v; })

      if (this.err.length > 0) {
        Text(this.err)
          .fontSize(11.5).fontColor(tc(this.dark, '#B4483C', 1))
          .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(10).backgroundColor(tc(this.dark, '#FDF0EE', 0))
          .border({ width: 1, color: tc(this.dark, tc(this.dark, '#F8DCD7', 2), 2) })
          .margin({ top: 9 })
      }

      // .tags: 四个来源胶囊 + 最右「记下」（没有取消按钮）
      Row({ space: 6 }) {
        ForEach(TAGS, (t: string) => {
          Text(t)
            .fontSize(10.5)
            .fontColor(this.tag === t ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#6A7F92', 1))
            .fontWeight(this.tag === t ? FontWeight.Medium : FontWeight.Normal)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor(this.tag === t ? tk(this.dark, 'brandSoft') : tc(this.dark, '#FFFFFF', 0))
            .border({ width: 1, color: this.tag === t ? tk(this.dark, 'brandLine') : tk(this.dark, 'line') })
            .onClick(() => { this.tag = t; })
        }, (t: string) => `qc-${t}`)
        Blank()
        Text(this.busy ? '保存中…' : '记下')
          .fontSize(12).fontColor(onFill(this.dark)).fontWeight(FontWeight.Medium)
          .height(34).padding({ left: 16, right: 16 })
          .borderRadius(11).textAlign(TextAlign.Center)
          .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
          .opacity(this.busy ? 0.6 : 1)
          .onClick(() => { if (!this.busy) { this.save(); } })
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .border({ width: 1, color: tk(this.dark, 'line') })
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .shadow({ radius: 45, color: 'rgba(23,52,80,0.20)', offsetX: 0, offsetY: 15 })
  }
}
