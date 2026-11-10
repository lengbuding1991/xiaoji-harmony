// 全局搜索
// 对齐「个人工作台」app/(app)/search/page.tsx：搜索框 + 类型筛选 + 结果列表
// （任务 / 记录 / 日程 / 复盘，带类型标签、日期、摘要片段）。
import { Store } from '../store/Store';
import { C, onFill, S, tc, tk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { sym } from '../components/Icon';
import { Chip } from '../components/Widgets';
import { SearchHit } from '../api/Types';
import { TopBar } from '../components/TopBar';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

interface KindMeta {
  label: string;
  bg: string;
  fg: string;
}

@Component
export struct SearchView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State q: string = '';
  @State kind: string = 'all';
  @State hits: SearchHit[] = [];
  @State total: number = 0;
  @State searching: boolean = false;
  @Prop showTop: boolean = true;
  @State searched: boolean = false;
  // v4.5：边打边搜的防抖计时器
  private timer: number = -1;
  @State counts: number[] = [0, 0, 0, 0];   // task / note / event / review
  onNavigate: (page: string) => void = () => {};

  private kinds(): string[] { return ['task', 'note', 'event', 'review']; }

  private meta(k: string): KindMeta {
    // v4.21：fg 压在同色浅底上，重算到 >=4.55:1
    if (k === 'task') { return { label: '任务', bg: '#E8F2FC', fg: '#2970AD' } as KindMeta; }
    if (k === 'note') { return { label: '记录', bg: '#E3F8F2', fg: '#287B68' } as KindMeta; }
    if (k === 'event') { return { label: '日程', bg: '#E9F3FB', fg: '#387199' } as KindMeta; }
    return { label: '复盘', bg: '#F1ECFE', fg: '#7355D0' } as KindMeta;
  }

  private countOf(k: string): number {
    let n = 0;
    for (const h of this.hits) { if (h.kind === k) { n += 1; } }
    return n;
  }

  private async run(): Promise<void> {
    const q: string = this.q.trim();
    if (q.length === 0) {
      this.hits = [];
      this.total = 0;
      this.searched = false;
      return;
    }
    this.searching = true;
    const r = await Store.I.search(q, this.kind);
    this.searching = false;
    this.hits = r.hits;
    this.total = r.total;
    this.searched = true;
    // v4.4：分项计数用服务端给的（未截断的）数，跟「共 N 条」同源
    this.counts = r.counts && r.counts.length === 4
      ? r.counts : [this.countOf('task'), this.countOf('note'), this.countOf('event'), this.countOf('review')];
  }

  private switchKind(k: string): void {
    if (this.kind === k) { return; }
    this.kind = k;
    if (this.q.trim().length > 0) { this.run(); }
  }

  private whenOf(h: SearchHit): string {
    if (h.at.length < 10) { return ''; }
    return D.dateOf(h.at).replace(/-/g, '/');
  }

  private openHit(h: SearchHit): void {
    if (h.kind === 'task') { this.onNavigate('tasks'); }
    else if (h.kind === 'note') { this.onNavigate('notes'); }
    else if (h.kind === 'event') { this.onNavigate('calendar'); }
    else { this.onNavigate('review'); }
  }

  @Builder hitRow(h: SearchHit) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(this.meta(h.kind).label)
          .fontSize(8.5).fontColor(this.meta(h.kind).fg)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(5)
          .backgroundColor(this.meta(h.kind).bg)
        Text(h.title.length > 0 ? h.title : '(无标题)')
          .fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#2B4055', 1))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.whenOf(h)).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1)).flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (h.snippet.length > 0) {
        Text(h.snippet)
          .fontSize(10).fontColor(tc(this.dark, '#8FA2B3', 1))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .border({ width: { bottom: 1 }, color: tc(this.dark, '#F2F7FB', 2) })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => { this.openHit(h); })
  }

  build() {
    Scroll() {
      Column() {
        // 搜索页顶部只留搜索与返回图标（工作台此页 TopBar 只有搜索与日期）
        if (this.showTop) {
          TopBar({
            showBell: false,
            showSearch: false,   // v4.4：页面自己就有输入框，顶部再放一个空的放大镜没用
            onSearch: () => { },
            onCalendar: () => { this.onNavigate('calendar'); }
          })
            .width('100%')
        }

        // page-head
        Column({ space: 5 }) {
          Text('SEARCH · 全文搜索').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
          Text(this.q.trim().length > 0 ? `“${this.q.trim()}” 的结果` : '找一件事。')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.searched
            ? `共 ${this.total} 条（任务 ${this.counts[0]} · 记录 ${this.counts[1]} · 日程 ${this.counts[2]} · 复盘 ${this.counts[3]}）`
            : '搜索任务、记录、日程和复盘。多个关键词用空格分开，会要求全部命中。')
            .fontSize(11).fontColor(tk(this.dark, 'textSub'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14, bottom: 14 })

        // 搜索表单
        Column({ space: 9 }) {
          Row({ space: 8 }) {
            SymbolGlyph(sym('search')).fontSize(13).fontColor([tc(this.dark, '#A2B3C2', 1)])
            TextInput({ placeholder: '关键词，空格分隔多个…', text: this.q })
              .fontSize(12).height(34).layoutWeight(1)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor('#00000000').padding(0)
              .enterKeyType(EnterKeyType.Search)
              .onChange((v: string) => {
                this.q = v;
                // v4.5：边打边搜（网页版是实时搜的），不用非要点一下「搜索」
                if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
                if (v.trim().length > 0) {
                  this.timer = setTimeout(() => { this.timer = -1; this.run(); }, 260);
                }
                // v4.4：手动退格清空输入时，旧结果还留在页面上（标题已经变成「找一件事。」了）
                if (v.trim().length === 0) {
                  this.hits = [];
                  this.total = 0;
                  this.searched = false;
                  this.counts = [0, 0, 0, 0];
                }
              })
              .onSubmit(() => { this.run(); })
            if (this.q.length > 0) {
              SymbolGlyph(sym('close')).fontSize(13).fontColor([tc(this.dark, '#C3D2DE', 1)])
                .onClick(() => {
                  this.q = '';
                  this.hits = [];
                  this.searched = false;
                  this.total = 0;
                  this.counts = [0, 0, 0, 0];
                })
            }
            Text(this.searching ? '搜…' : '搜索')
              .fontSize(11).fontColor(onFill(this.dark))
              .padding({ left: 13, right: 13, top: 6, bottom: 6 })
              .borderRadius(9)
              .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
              .onClick(() => { this.run(); })
          }
          .width('100%')
          .padding({ left: 12, right: 6, top: 5, bottom: 5 })
          .borderRadius(11)
          .backgroundColor(tc(this.dark, '#F8FBFE', 0))
          .border({ width: 1, color: tk(this.dark, 'line') })
          .alignItems(VerticalAlign.Center)

          Row({ space: 6 }) {
            Chip({ text: '全部', active: this.kind === 'all', onTap: () => { this.switchKind('all'); } })
            Chip({ text: '任务', active: this.kind === 'task', onTap: () => { this.switchKind('task'); } })
            Chip({ text: '记录', active: this.kind === 'note', onTap: () => { this.switchKind('note'); } })
            Chip({ text: '日程', active: this.kind === 'event', onTap: () => { this.switchKind('event'); } })
            Chip({ text: '复盘', active: this.kind === 'review', onTap: () => { this.switchKind('review'); } })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 15, right: 15, top: 13, bottom: 13 })
        .borderRadius(18)
        .backgroundColor(tk(this.dark, 'card'))
        .border({ width: 1, color: tk(this.dark, 'cardBorder') })
        .alignItems(HorizontalAlign.Start)

        // 空态 / 结果
        if (!this.searched) {
          Column({ space: 5 }) {
            Text('输入一个关键词开始').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5E7183', 1))
            Text('试试「周报」「读书」「下周」。').fontSize(10.5).fontColor(tc(this.dark, '#A8B8C6', 1))
          }
          .width('100%')
          .padding({ top: 54, bottom: 54 })
          .borderRadius(S.radiusCard)
          .backgroundColor(tk(this.dark, 'card'))
          .border({ width: 1, color: tk(this.dark, 'cardBorder') })
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 14 })
        } else if (this.hits.length === 0) {
          Column({ space: 5 }) {
            Text('没有找到').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5E7183', 1))
            Text('换个词，或换个类型再试。').fontSize(10.5).fontColor(tc(this.dark, '#A8B8C6', 1))
          }
          .width('100%')
          .padding({ top: 54, bottom: 54 })
          .borderRadius(S.radiusCard)
          .backgroundColor(tk(this.dark, 'card'))
          .border({ width: 1, color: tk(this.dark, 'cardBorder') })
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 14 })
        } else {
          Column({ space: 0 }) {
            Row({ space: 8 }) {
              Text('结果').fontSize(13.5).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text'))
              Text(`${this.total}`).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
              Blank()
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 13, bottom: 6 })

            Column({ space: 0 }) {
              ForEach(this.hits, (h: SearchHit) => {
                this.hitRow(h)
              }, (h: SearchHit) => `${h.kind}-${h.id}`)
            }
            .width('100%')
            .padding({ bottom: 4 })
          }
          .width('100%')
          .borderRadius(S.radiusCard)
          .backgroundColor(tk(this.dark, 'card'))
          .border({ width: 1, color: tk(this.dark, 'cardBorder') })
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 14, bottom: S.pageBottom })
        }
      }
      .width('100%')
      .padding({ left: S.pagePad, right: S.pagePad, top: S.pageTop })
      .alignItems(HorizontalAlign.Start)
    }
    .onScrollEdge(onEdgeScrolled)
    .onWillScroll(onEdgeWillScroll)
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .constraintSize({ maxWidth: 1240 })
    .backgroundColor(tk(this.dark, 'bg'))
    .edgeEffect(EdgeEffect.Spring)
  }
}
