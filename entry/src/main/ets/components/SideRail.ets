// entry/src/main/ets/components/SideRail.ets
// v4.6：宽屏（平板 / 折叠屏展开）用的左侧导航栏。
// 逐条对齐网页端「个人工作台」的 components/Sidebar.tsx：
//   brand（渐变方块 + 小记 + XIAOJI）
//   tagline（安排好行动，让生活慢慢生长。）
//   nav（primary 四项 + secondary 五项，选中态淡青底 + 深青字）
//   side-foot（头像 + 名字 + 设置齿轮）
// 手机上不显示这个（手机上还是底部导航）。

import { brandGradient, C, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from './Icon';
import { Store } from '../store/Store';
import { R } from '../utils/Responsive';

interface RailItem {
  key: string;
  icon: string;
  label: string;
}

@Component
export struct SideRail {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  /** 当前所在页面（home/tasks/calendar/notes 或二级页 key）
   *  v4.6 修：必须是 @Prop —— 普通成员变量父组件改不了它，
   *  结果就是切了页面左边还一直高亮第一项。 */
  @Prop active: string = 'home';
  /** 点导航项 */
  onNavigate: (key: string) => void = () => {};
  /** 设置页里的称呼 */
  @State userName: string = '';
  private unsub: (() => void) | null = null;

  private readonly primary: RailItem[] = [
    { key: 'home', icon: 'home', label: '成长总览' } as RailItem,
    { key: 'tasks', icon: 'tasks', label: '任务面板' } as RailItem,
    { key: 'calendar', icon: 'calendar', label: '日历安排' } as RailItem,
    { key: 'notes', icon: 'note', label: '记录灵感' } as RailItem
  ];

  private readonly secondary: RailItem[] = [
    { key: 'habits', icon: 'flame', label: '每日习惯' } as RailItem,
    { key: 'projects', icon: 'folder', label: '项目进度' } as RailItem,
    { key: 'review', icon: 'undo', label: '每日复盘' } as RailItem,
    { key: 'stats', icon: 'grid', label: '数据洞察' } as RailItem,
    { key: 'search', icon: 'search', label: '全局搜索' } as RailItem,
    { key: 'settings', icon: 'gear', label: '设置' } as RailItem
  ];

  aboutToAppear(): void {
    this.userName = Store.I.settings.user_name;
    this.unsub = Store.I.subscribe(() => {
      this.userName = Store.I.settings.user_name;
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  @Builder navItem(it: RailItem) {
    Row({ space: 11 }) {
      SymbolGlyph(sym(it.icon))
        .fontSize(17)
        .fontColor([this.active === it.key ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#8FA3B6', 1)])
      Text(it.label)
        .fontSize(12.5)
        .fontColor(this.active === it.key ? tkInk(this.dark, 'brandDeep') : tk(this.dark, 'text'))
        .fontWeight(this.active === it.key ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .padding({ top: 9, bottom: 9, left: 11, right: 11 })
    .borderRadius(12)
    .backgroundColor(this.active === it.key ? tk(this.dark, 'brandSoft') : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onNavigate(it.key);
    })
  }

  @Builder brand() {
    Row({ space: 10 }) {
      Row() {
        SymbolGlyph(sym('grid')).fontSize(17).fontColor([onFill(this.dark)])
      }
      .width(34).height(34).borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .linearGradient(brandGradient())
      Column({ space: 2 }) {
        Text('小记')
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text'))
        Text('XIAOJI')
          .fontSize(9).fontColor(tk(this.dark, 'textHint')).letterSpacing(1.6)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder foot() {
    Row({ space: 9 }) {
      Row() {
        Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '我')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(onFill(this.dark))
      }
      .width(30).height(30).borderRadius(15)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .linearGradient(brandGradient())
      Text(this.userName.length > 0 ? this.userName : '我')
        .fontSize(12).fontColor(tk(this.dark, 'text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph(sym('gear'))
        .fontSize(16)
        .fontColor([tc(this.dark, '#9BAFC0', 1)])
        .onClick(() => {
          this.onNavigate('settings');
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 10 })
    .border({ width: { top: 1 }, color: tk(this.dark, 'line') })
  }

  build() {
    Column() {
      this.brand()

      Text('安排好行动，让生活慢慢生长。')
        .fontSize(10).fontColor(tk(this.dark, 'textSub'))
        .width('100%')
        .margin({ top: 8, bottom: 12 })

      Column({ space: 2 }) {
        ForEach(this.primary, (it: RailItem) => {
          this.navItem(it)
        }, (it: RailItem) => `rail-p-${it.key}`)
      }
      .width('100%')

      Divider()
        .color(tk(this.dark, 'line'))
        .margin({ top: 10, bottom: 10 })

      Column({ space: 2 }) {
        ForEach(this.secondary, (it: RailItem) => {
          this.navItem(it)
        }, (it: RailItem) => `rail-s-${it.key}`)
      }
      .width('100%')

      Blank()

      this.foot()
    }
    .width(R.railW())
    .height('100%')
    .padding({ left: 14, right: 14, top: 20, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(tc(this.dark, '#FFFFFF', 0))
    .border({ width: { right: 1 }, color: tk(this.dark, 'line') })
  }
}
