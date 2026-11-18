// 顶部栏：对齐「个人工作台」手机端的 TopBar（components/TopBar.tsx + globals.css）
//   CSS 依据（@media max-width:640px）：
//     .top .crumb,.top .today{display:none}
//     .top-right{margin-left:auto;gap:6px}
//     .top-right .ghost,.top-right .primary{padding:6px 9px;font-size:10px}
//   铃铛弹层对齐 .bell-pop（白卡 radius 15、宽 300、padding 13、阴影 0 20px 60px rgba(23,52,80,.16)）。
import { Store } from '../store/Store';
import { brandGradient, cardShadow, glassEffect, onFill, S, tc, tk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { sym } from './Icon';
import { ReminderItem } from '../api/Types';

@Component
export struct TopBar {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
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
  // 页面自己的名字在正文的 eyebrow（如「HABITS · 习惯打卡」）里。

  // v5.17：二级页返回按钮（以前二级页只能靠底部导航/侧栏跳走，没有「返回」）
  @Prop backLabel: string = '';
  onBack: () => void = () => {};
  onPrimary: () => void = () => {};
  onSecondary: () => void = () => {};
  onSearch: () => void = () => {};
  onCalendar: () => void = () => {};

  @State bellOpen: boolean = false;
  // v5.7：铃铛红点「未读数」。
  //   必须先算进 @State 再在 UI 里直接读 —— ArkUI V1 只重画「属性表达式里直接读过 state」的节点，
  //   在方法里读 Store.I.reminders 不会触发刷新（老坑，见开发文档 §16.1）。
  @State bellUnread: number = 0;
  // v5.11：铃铛弹层里显示的是「打开这一刻的未读快照」——
  //   看过就不再显示（提醒一次就行），最多 5 条。
  @State bellItems: ReminderItem[] = [];
  @State bellMore: number = 0;
  private unsubBell: () => void = () => {};

  aboutToAppear(): void {
    this.syncBell();
    this.unsubBell = Store.I.subscribe(() => { this.syncBell(); });
  }

  aboutToDisappear(): void {
    this.unsubBell();
  }

  private syncBell(): void {
    this.bellUnread = Store.I.bellUnread();
  }

  /** 打开弹层：抓一份未读快照（最多 5 条），然后全部标记为已读 ⇒ 红点灭 */
  private openBell(): void {
    const pending: ReminderItem[] = Store.I.bellUnreadItems();
    this.bellMore = pending.length > 5 ? pending.length - 5 : 0;
    this.bellItems = pending.length > 5 ? pending.slice(0, 5) : pending;
    Store.I.markBellSeen();
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

  // v5.15 可访问性：可点区域必须 ≥40×40。
  //   原来整块就 34×34，手指偏一点就点空 ⇒ 外面套一层 40×40 的透明热区，
  //   里面的玻璃小芯片仍然是 34×34（视觉一点没变胖）。
  //   label 是给读屏软件念的（原来全项目一个无障碍标签都没有）。
  @Builder iconBtn(icon: string, label: string, cb: () => void) {
    Row() {
      Row() {
        SymbolGlyph(sym(icon)).fontSize(S.headSize).fontColor([tk(this.pal, 'textSub')])
      }
      .width(34)
      .height(34)
      .borderRadius(S.radiusInner)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(tc(this.pal, '#FFFFFF', 0))
      .border({ width: 1, color: tk(this.pal, 'line') })
      // v5.0：真水晶小芯片（毛玻璃 + 提饱和），按钮底下的页面内容会透过来
      .backgroundEffect(glassEffect(14))
      // v5.0：按压回弹
      .stateStyles({ pressed: { .scale({ x: 0.92, y: 0.92 }) } })
      .animation({ duration: 130, curve: Curve.EaseOut })
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(cb)
    // v5.15：图标按钮光看图标猜不出干什么 ⇒ 给一句人话
    .accessibilityText(label)
  }

  // v5.15 可访问性：按钮高 34 → 40，保证可点区域 ≥40×40
  @Builder primaryBtn() {
    Row({  space: S.spaceSm  }) {
      SymbolGlyph(sym('plus')).fontSize(S.cardTitleSize).fontColor([onFill(this.pal)])
      Text(this.primaryText).fontSize(S.labelSize).fontWeight(FontWeight.Medium).fontColor(onFill(this.pal))
    }
    .height(40)
    .padding({  left: S.space3Xl, right: S.space3Xl  })
    .borderRadius(S.radiusBtn)
    .alignItems(VerticalAlign.Center)
    .linearGradient(brandGradient(this.pal))
    .shadow(cardShadow(this.pal))
    .onClick(() => { this.onPrimary(); })
    // v5.15：主按钮的读屏文案 = 按钮上的字（如「添加任务」「新日程」）
    .accessibilityText(this.primaryText)
    // v5.0：按压回弹
    .stateStyles({ pressed: { .scale({ x: 0.95, y: 0.95 }) } })
    .animation({ duration: 130, curve: Curve.EaseOut })
  }

  // v5.15 可访问性：按钮高 34 → 40，保证可点区域 ≥40×40
  @Builder secondaryBtn() {
    Text(this.secondaryText)
      .fontSize(S.subSize)
      .fontColor(tc(this.pal, '#6A7F92', 1))
      .height(40)
      .padding({  left: S.space2Xl, right: S.space2Xl  })
      .borderRadius(S.radiusBtn)
      .textAlign(TextAlign.Center)
      .backgroundColor(tc(this.pal, '#FFFFFF', 0))
      .border({ width: 1, color: tk(this.pal, 'line') })
      .onClick(() => { this.onSecondary(); })
      // v5.15：次按钮的读屏文案 = 按钮上的字
      .accessibilityText(this.secondaryText)
    // v5.0：按压回弹
    .stateStyles({ pressed: { .scale({ x: 0.95, y: 0.95 }) } })
    .animation({ duration: 130, curve: Curve.EaseOut })
  }

  // 铃铛弹层：对齐 .bell-pop / .bell-head / .bell-item / .bell-dot
  @Builder bellPop() {
    Column({  space: 0  }) {
      Row() {
        Text('提醒清单').fontSize(S.smallSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text'))
        Blank()
        Text(`${this.bellItems.length} 条`).fontSize(S.microSize).fontColor(tk(this.pal, 'textHint'))
      }
      .width('100%')
      .margin({  bottom: S.spaceMd  })

      if (this.bellItems.length === 0) {
        Text('没有新的提醒了。')
          .fontSize(S.subSize)
          .fontColor(tk(this.pal, 'textHint'))
          .width('100%')
          .padding({  top: S.spaceXl, bottom: S.spaceXl  })
      } else {
        ForEach(this.bellItems, (it: ReminderItem) => {
          Row({  space: S.spaceLg  }) {
            Row()
              .width(6)
              .height(6)
              .borderRadius(S.radiusDot)
              .backgroundColor(it.kind === 'event' ? tk(this.pal, 'event') : tk(this.pal, 'brand'))
              .margin({  top: S.spaceLg  })
            Column({  space: S.spaceXs  }) {
              Text(it.title).fontSize(S.labelSize).fontColor(tk(this.pal, 'text')).lineHeight(16).width('100%')
              Text(`${this.whenText(it)}${it.overdue ? '' : ' · ' + (it.kind === 'event' ? '日程' : '任务')}`)
                .fontSize(S.microSize)
                .fontColor(tk(this.pal, 'textHint'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({  top: S.spaceLg, bottom: S.spaceLg  })
          .alignItems(VerticalAlign.Top)
          .border({ width: { bottom: 1 }, color: '#F2F7FB' })
        }, (it: ReminderItem) => `${it.kind}-${it.id}`)
        if (this.bellMore > 0) {
          Text(`还有 ${this.bellMore} 条，去任务面板看`)
            .fontSize(S.microSize)
            .fontColor(tk(this.pal, 'textHint'))
            .width('100%')
            .padding({  top: S.spaceLg  })
        }
      }
    }
    .width(268)
    .padding(13)
    .backgroundColor(tc(this.pal, '#FFFFFF', 0))
    .borderRadius(S.radiusCard)
    .border({ width: 1, color: tk(this.pal, 'line') })
  }

  @Builder bellBtn() {
    Stack() {
      this.iconBtn('bell', '提醒', () => {
        this.bellOpen = !this.bellOpen;
        // v5.11：打开提醒清单 = 一次性提醒。抓一份未读快照（最多 5 条）显示，
        //   同时全部标记已读 ⇒ 红点当场灭；关掉再打开，里面就是空的。
        if (this.bellOpen) {
          this.openBell();
        }
      })
      if (this.bellUnread > 0) {
        Row()
          .width(7)
          .height(7)
          .borderRadius(S.radiusXs)
          .backgroundColor(tc(this.pal, '#A83440', 0))
          // v5.15：热区从 34 变 40 了，红点跟着挪到芯片的右上角（视觉位置不变）
          .position({ x: 28, y: 8 })
      }
    }
    // v5.11：改用单向绑定 + onWillDismiss 手动复位。
    //   原来用 $$this.bellOpen：点外部/返回键关掉弹层时，框架不会把 false 写回 state，
    //   于是再点一次铃铛会「差一次」（先关后开）。现在由 onWillDismiss 统一复位。
    .bindPopup(this.bellOpen, {
      builder: this.bellPop(),
      placement: Placement.BottomRight,
      popupColor: '#FFFFFF',
      radius: 15,
      autoCancel: true,
      mask: false,
      onWillDismiss: (action: DismissPopupAction) => {
        action.dismiss();
        this.bellOpen = false;
      }
    })
  }

  // v5.17：二级页左上角的「‹ 返回」
  @Builder backBtn() {
    Row({  space: S.spaceXs  }) {
      SymbolGlyph(sym('left')).fontSize(S.iconSize).fontColor([tk(this.pal, 'textSub')])
      Text(this.backLabel).fontSize(S.bodySize).fontColor(tk(this.pal, 'textSub'))
    }
    .height(40)
    .padding({  left: S.spaceMd, right: S.space2Xl  })
    .borderRadius(S.radiusBtn)
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.onBack(); })
    .accessibilityText(`返回${this.backLabel}`)
  }

  build() {
    Row({  space: S.spaceMd  }) {
      if (this.backLabel.length > 0) {
        this.backBtn()
      }
      Blank()
      if (this.showSearch) {
        this.iconBtn('search', '搜索', () => { this.onSearch(); })
      }
      if (this.showBell) {
        this.bellBtn()
      }
      if (this.showCalendar) {
        this.iconBtn('calendar', '日历', () => { this.onCalendar(); })
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
