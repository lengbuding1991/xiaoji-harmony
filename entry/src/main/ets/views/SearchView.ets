// 搜索
// 对齐「个人工作台」app/(app)/search/page.tsx：搜索框 + 类型筛选 + 结果列表
// （任务 / 记录 / 日程 / 复盘，带类型标签、日期、摘要片段）。
import { Store } from '../store/Store';
import { S, brandGradient, catBg, catColor, misc, onFill, tc, tk, tkInk } from '../utils/Theme';
import { R } from '../utils/Responsive';
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
  @StorageLink('wb_pal') pal: number = 0;
  @State q: string = '';
  @State kind: string = 'all';
  @State hits: SearchHit[] = [];
  @State total: number = 0;
  @State searching: boolean = false;
  @Prop showTop: boolean = true;
  @State searched: boolean = false;
  // v5.14：搜索失败的原因（空结果有两种：真的没有 / 搜索坏了，别混成一种）
  @State searchErr: string = '';
  // v4.5：边打边搜的防抖计时器
  private timer: number = -1;
  @State counts: number[] = [0, 0, 0, 0];   // task / note / event / review
  onNavigate: (page: string) => void = () => {};
  // v5.17：二级页返回（Index 传进来的）
  onBack: () => void = () => {};

  private kinds(): string[] { return ['task', 'note', 'event', 'review']; }

  private meta(k: string): KindMeta {
    // v4.21：fg 压在同色浅底上，重算到 >=4.55:1
    if (k === 'task') { return { label: '任务', bg: catBg(this.pal, 'work'), fg: catColor(this.pal, 'work') } as KindMeta; }
    if (k === 'note') { return { label: '记录', bg: catBg(this.pal, 'study'), fg: catColor(this.pal, 'study') } as KindMeta; }
    if (k === 'event') { return { label: '日程', bg: misc(this.pal, 'metaEventBg', '#E9F3FB'), fg: misc(this.pal, 'metaEventFg', '#387199') } as KindMeta; }
    return { label: '复盘', bg: catBg(this.pal, 'side'), fg: catColor(this.pal, 'side') } as KindMeta;
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
      this.searchErr = '';
      return;
    }
    this.searching = true;
    const r = await Store.I.search(q, this.kind);
    this.searching = false;
    this.hits = r.hits;
    this.total = r.total;
    this.searched = true;
    // v5.14：记下这次是不是「搜索本身坏了」
    this.searchErr = Store.I.searchError;
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
    Column({  space: S.spaceSm  }) {
      Row({  space: S.spaceMd  }) {
        Text(this.meta(h.kind).label)
          .fontSize(S.microSize).fontColor(this.meta(h.kind).fg)
          .padding({  left: S.spaceMd, right: S.spaceMd, top: S.spaceXs, bottom: S.spaceXs  })
          .borderRadius(S.radiusXs)
          .backgroundColor(this.meta(h.kind).bg)
        Text(h.title.length > 0 ? h.title : '(无标题)')
          .fontSize(S.bodySize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#2B4055', 1))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.whenOf(h)).fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1)).flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (h.snippet.length > 0) {
        Text(h.snippet)
          .fontSize(S.subSize).fontColor(tc(this.pal, '#8FA2B3', 1))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding({  left: S.space2Xl, right: S.space2Xl, top: S.space2Xl, bottom: S.space2Xl  })
    .border({ width: { bottom: 1 }, color: tc(this.pal, '#F2F7FB', 2) })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => { this.openHit(h); })
  }

  build() {
    Scroll() {
      Column() {
        // 搜索页顶部只留搜索与返回图标（工作台此页 TopBar 只有搜索与日期）
        if (this.showTop) {
          TopBar({
      backLabel: '返回',
      onBack: () => { this.onBack(); },
            showBell: false,
            showSearch: false,   // v4.4：页面自己就有输入框，顶部再放一个空的放大镜没用
            onSearch: () => { },
            onCalendar: () => { this.onNavigate('calendar'); }
          })
            .width('100%')
        }

        // page-head
        Column({  space: S.spaceMd  }) {
          Text('SEARCH · 搜索').fontSize(S.tinySize).fontColor(tc(this.pal, '#9DB0C1', 1)).letterSpacing(1.6)
          Text(this.q.trim().length > 0 ? `“${this.q.trim()}” 的结果` : '找一件事。')
            .fontSize(S.sectionSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text')).letterSpacing(-0.2)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.searched
            ? `共 ${this.total} 项（任务 ${this.counts[0]} 件 · 记录 ${this.counts[1]} 条 · 日程 ${this.counts[2]} 个 · 复盘 ${this.counts[3]} 篇）`
            : '任务、记录、日程、复盘。多个词用空格分开。')
            .fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({  top: S.spaceXl, bottom: S.spaceXl  })

        // 搜索表单
        Column({  space: S.spaceXl  }) {
          Row({  space: S.spaceLg  }) {
            SymbolGlyph(sym('search')).fontSize(S.midSize).fontColor([tc(this.pal, '#A2B3C2', 1)])
            TextInput({ placeholder: '关键词，空格分隔多个…', text: this.q })
              .fontSize(S.smallSize).height(34).layoutWeight(1)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.pal, '#A8B8C6', 1))
              .fontColor(tk(this.pal, 'text'))
              .caretColor(tk(this.pal, 'brand'))
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
              .accessibilityText('搜索关键词')
            if (this.q.length > 0) {
              // v5.15 可访问性：清除按钮原来只有 13×13 ⇒ 外层套 40×40 的透明热区，× 本身不变
              Row() {
                SymbolGlyph(sym('close')).fontSize(S.midSize).fontColor([tc(this.pal, '#C3D2DE', 1)])
              }
              .width(40).height(40)
              .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.q = '';
                this.hits = [];
                this.searched = false;
                this.total = 0;
                this.counts = [0, 0, 0, 0];
              })
              .accessibilityText('清除搜索')
            }
            // v5.15 可访问性：「搜索」按钮原来只有 ~23 高 ⇒ 撑到 40
            Text(this.searching ? '搜…' : '搜索')
              .fontSize(S.labelSize).fontColor(onFill(this.pal))
              .height(40)
              .padding({  left: S.space3Xl, right: S.space3Xl  })
              .borderRadius(S.radiusSm)
              .textAlign(TextAlign.Center)
              .linearGradient(brandGradient(this.pal))
              .onClick(() => { this.run(); })
              .accessibilityText('搜索')
          }
          .width('100%')
          .padding({  left: S.space2Xl, right: S.spaceMd, top: S.spaceMd, bottom: S.spaceMd  })
          .borderRadius(S.radiusBtn)
          .backgroundColor(tc(this.pal, '#F8FBFE', 0))
          .border({ width: 1, color: tk(this.pal, 'line') })
          .alignItems(VerticalAlign.Center)

          Row({  space: S.spaceMd  }) {
            Chip({ text: '全部', active: this.kind === 'all', onTap: () => { this.switchKind('all'); } })
            Chip({ text: '任务', active: this.kind === 'task', onTap: () => { this.switchKind('task'); } })
            Chip({ text: '记录', active: this.kind === 'note', onTap: () => { this.switchKind('note'); } })
            Chip({ text: '日程', active: this.kind === 'event', onTap: () => { this.switchKind('event'); } })
            Chip({ text: '复盘', active: this.kind === 'review', onTap: () => { this.switchKind('review'); } })
          }
          .width('100%')
        }
        .width('100%')
        .padding({  left: 15, right: 15, top: S.space3Xl, bottom: S.space3Xl  })
        .borderRadius(S.radiusCard)
        .backgroundColor(tk(this.pal, 'card'))
        .border({ width: 1, color: tk(this.pal, 'cardBorder') })
        .alignItems(HorizontalAlign.Start)

        // 空态 / 结果
        if (!this.searched) {
          Column({  space: S.spaceMd  }) {
            Text('输入一个关键词开始').fontSize(S.bodySize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#5E7183', 1))
            Text('试试「周报」「读书」「下周」。').fontSize(S.subSize).fontColor(tc(this.pal, '#A8B8C6', 1))
          }
          .width('100%')
          .padding({  top: 54, bottom: 54  })
          .borderRadius(S.radiusCard)
          .backgroundColor(tk(this.pal, 'card'))
          .border({ width: 1, color: tk(this.pal, 'cardBorder') })
          .alignItems(HorizontalAlign.Center)
          .margin({  top: S.space3Xl  })
        } else if (this.hits.length === 0) {
          Column({  space: S.spaceMd  }) {
            // v5.14：搜索失败要说「搜索坏了」，不能也说「没有找到」——
            //   否则用户会以为自己写错词，其实是本地库出问题了。
            if (this.searchErr.length > 0) {
              Text('搜索没跑通').fontSize(S.bodySize).fontWeight(FontWeight.Medium).fontColor(tkInk(this.pal, 'danger'))
              // v5.15 可访问性：错误原因原来 10.5 灰字 ⇒ 12+ 危险色，看得见
              Text(this.searchErr).fontSize(S.smallSize).fontColor(tkInk(this.pal, 'danger'))
              Text('回上一页稍等一下再搜。').fontSize(S.smallSize).fontColor(tk(this.pal, 'textSub'))
            } else {
              Text('没有找到').fontSize(S.bodySize).fontWeight(FontWeight.Medium).fontColor(tc(this.pal, '#5E7183', 1))
              Text('换个词，或换个类型再试。').fontSize(S.subSize).fontColor(tc(this.pal, '#A8B8C6', 1))
            }
          }
          .width('100%')
          .padding({  top: 54, bottom: 54  })
          .borderRadius(S.radiusCard)
          .backgroundColor(tk(this.pal, 'card'))
          .border({ width: 1, color: tk(this.pal, 'cardBorder') })
          .alignItems(HorizontalAlign.Center)
          .margin({  top: S.space3Xl  })
        } else {
          Column({  space: 0  }) {
            Row({  space: S.spaceLg  }) {
              Text('结果').fontSize(S.midSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text'))
              Text(`${this.total}`).fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
              Blank()
            }
            .width('100%')
            .padding({  left: S.space3Xl, right: S.space3Xl, top: S.space3Xl, bottom: S.spaceMd  })

            Column({  space: 0  }) {
              ForEach(this.hits, (h: SearchHit) => {
                this.hitRow(h)
              }, (h: SearchHit) => `${h.kind}-${h.id}-${this.pal}`)
            }
            .width('100%')
            .padding({  bottom: S.spaceSm  })
          }
          .width('100%')
          .borderRadius(S.radiusCard)
          .backgroundColor(tk(this.pal, 'card'))
          .border({ width: 1, color: tk(this.pal, 'cardBorder') })
          .alignItems(HorizontalAlign.Start)
          .margin({  top: S.space3Xl, bottom: R.bottomPad()  })
        }
      }
      .width('100%')
      .padding({  left: S.pagePad, right: S.pagePad, top: S.pageTop  })
      .alignItems(HorizontalAlign.Start)
    }
      // v5.16：滚动时把右下角悬浮按钮藏起来（它正好压在内容上），停了就回来
      .onDidScroll((x: number, y: number) => { AppStorage.setOrCreate<boolean>('wb_scrolling', true); })
      .onScrollStop(() => { AppStorage.setOrCreate<boolean>('wb_scrolling', false); })
    .onScrollEdge(onEdgeScrolled)
    .onWillScroll(onEdgeWillScroll)
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .constraintSize({ maxWidth: 1240 })
    // v5.0：页面底色改成透明，让 Index 根 Stack 上的大光斑透出来
    .backgroundColor(Color.Transparent)
    .edgeEffect(EdgeEffect.Spring)
  }
}
