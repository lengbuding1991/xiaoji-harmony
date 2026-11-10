// 顶部栏：对齐「个人工作台」手机端的 TopBar（components/TopBar.tsx + globals.css）
//   CSS 依据（@media max-width:640px）：
//     .top .crumb,.top .today{display:none}
//     .top-right{margin-left:auto;gap:6px}
//     .top-right .ghost,.top-right .primary{padding:6px 9px;font-size:10px}
//   铃铛弹层对齐 .bell-pop（白卡 radius 15、宽 300、padding 13、阴影 0 20px 60px rgba(23,52,80,.16)）。
import { Store } from '../store/Store';
import { C, onFill, tc, tk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { sym } from './Icon';
import { ReminderItem } from '../api/Types';

@Component
export struct TopBar {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  // 主操作（渐变胶囊），空字符串表示这一页没有主操作
  @Prop primaryText: string = '';
  // 次要操作（白底描边胶囊），如「多选」「AI 起稿」
  @Prop secondaryText: string = '';
  @Prop showBell: boolean = true;
  // v4.4：搜索页顶部那个放大镜是空实现（点了没反应）⇒ 给个开关，搜索页关掉
  @Prop showSearch: boolean = true;
  // v4.7：协议正文页不该有日历/搜索入口（那是别的页面的功能）⇒ 给个开关关掉
  @Prop showCalendar: boolean = true;
  // v4.6：原来左上角有个「‹ 页面名」的返回按钮（crumb）——
  // 手机端有底部导航、平板端有左侧导航，都不需要它 ⇒ 整个去掉。
  // 页面自己的名字在正文的 eyebrow（如「HABITS · 每日习惯」）里。

  onPrimary: () => void = () => {};
  onSecondary: () => void = () => {};
  onSearch: () => void = () => {};
  onCalendar: () => void = () => {};

  @State bellOpen: boolean = false;

  private overdueCount(): number {
    let n: number = 0;
    const list: ReminderItem[] = Store.I.reminders;
    for (let i = 0; i < list.length; i++) {
      if (list[i].overdue) {
        n++;
      }
    }
    return n;
  }

  private whenText(it: ReminderItem): string {
    if (it.overdue) {
      return '已逾期';
    }
    if (it.at.length >= 16) {
      return D.hm(it.at);
    }
    return it.at;
  }

  @Builder iconBtn(icon: string, cb: () => void) {
    Row() {
      SymbolGlyph(sym(icon)).fontSize(15).fontColor([tk(this.dark, 'textSub')])
    }
    .width(34)
    .height(34)
    .borderRadius(12)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .border({ width: 1, color: tk(this.dark, 'line') })
    .onClick(cb)
  }

  @Builder primaryBtn() {
    Row({ space: 4 }) {
      SymbolGlyph(sym('plus')).fontSize(14).fontColor([onFill(this.dark)])
      Text(this.primaryText).fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(onFill(this.dark))
    }
    .height(34)
    .padding({ left: 13, right: 13 })
    .borderRadius(11)
    .alignItems(VerticalAlign.Center)
    .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
    .shadow({ radius: 22, color: 'rgba(51,169,214,0.26)', offsetX: 0, offsetY: 10 })
    .onClick(() => { this.onPrimary(); })
  }

  @Builder secondaryBtn() {
    Text(this.secondaryText)
      .fontSize(10.5)
      .fontColor(tc(this.dark, '#6A7F92', 1))
      .height(34)
      .padding({ left: 11, right: 11 })
      .borderRadius(11)
      .textAlign(TextAlign.Center)
      .backgroundColor(tc(this.dark, '#FFFFFF', 0))
      .border({ width: 1, color: tk(this.dark, 'line') })
      .onClick(() => { this.onSecondary(); })
  }

  // 铃铛弹层：对齐 .bell-pop / .bell-head / .bell-item / .bell-dot
  @Builder bellPop() {
    Column({ space: 0 }) {
      Row() {
        Text('提醒清单').fontSize(12).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text'))
        Blank()
        Text(`${Store.I.reminders.length} 条`).fontSize(8).fontColor(tk(this.dark, 'textHint'))
      }
      .width('100%')
      .margin({ bottom: 6 })

      if (Store.I.reminders.length === 0) {
        Text('暂时没有要提醒的事。')
          .fontSize(10.5)
          .fontColor(tk(this.dark, 'textHint'))
          .width('100%')
          .padding({ top: 10, bottom: 10 })
      } else {
        ForEach(Store.I.reminders, (it: ReminderItem) => {
          Row({ space: 8 }) {
            Row()
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(it.kind === 'event' ? tk(this.dark, 'event') : tk(this.dark, 'brand'))
              .margin({ top: 7 })
            Column({ space: 1 }) {
              Text(it.title).fontSize(11).fontColor(tk(this.dark, 'text')).lineHeight(16).width('100%')
              Text(`${this.whenText(it)}${it.overdue ? '' : ' · ' + (it.kind === 'event' ? '日程' : '任务')}`)
                .fontSize(8.5)
                .fontColor(tk(this.dark, 'textHint'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Top)
          .border({ width: { bottom: 1 }, color: '#F2F7FB' })
        }, (it: ReminderItem) => `${it.kind}-${it.id}`)
      }
    }
    .width(268)
    .padding(13)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .borderRadius(15)
    .border({ width: 1, color: tk(this.dark, 'line') })
  }

  @Builder bellBtn() {
    Stack() {
      this.iconBtn('bell', () => { this.bellOpen = !this.bellOpen; })
      if (this.overdueCount() > 0) {
        Row()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(tc(this.dark, '#E08A6F', 0))
          .position({ x: 25, y: 5 })
      }
    }
    .bindPopup($$this.bellOpen, {
      builder: this.bellPop(),
      placement: Placement.BottomRight,
      popupColor: '#FFFFFF',
      radius: 15,
      autoCancel: true,
      mask: false
    })
  }

  build() {
    Row({ space: 6 }) {
      Blank()
      if (this.showSearch) {
        this.iconBtn('search', () => { this.onSearch(); })
      }
      if (this.showBell) {
        this.bellBtn()
      }
      if (this.showCalendar) {
        this.iconBtn('calendar', () => { this.onCalendar(); })
      }
      if (this.secondaryText.length > 0) {
        this.secondaryBtn()
      }
      if (this.primaryText.length > 0) {
        this.primaryBtn()
      }
    }
    .width('100%')
    .height(46)
    .alignItems(VerticalAlign.Center)
  }
}
