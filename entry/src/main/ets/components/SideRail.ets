// entry/src/main/ets/components/SideRail.ets
// v4.6：宽屏（平板 / 折叠屏展开）用的左侧导航栏。
// 逐条对齐网页端「个人工作台」的 components/Sidebar.tsx：
//   brand（渐变方块 + 小记 + XIAOJI）
//   tagline（安排好行动，让生活慢慢生长。）
//   nav（primary 四项 + secondary 五项，选中态淡青底 + 深青字）
//   side-foot（头像 + 名字 + 设置齿轮）
// 手机上不显示这个（手机上还是底部导航）。

import { brandGradient, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from './Icon';
import { Store } from '../store/Store';
import { Layout, R } from '../utils/Responsive';

interface RailItem {
  key: string;
  icon: string;
  label: string;
}

@Component
export struct SideRail {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  /** 当前所在页面（home/tasks/calendar/notes 或二级页 key）
   *  v4.6 修：必须是 @Prop —— 普通成员变量父组件改不了它，
   *  结果就是切了页面左边还一直高亮第一项。 */
  @Prop active: string = 'home';
  /** 点导航项 */
  onNavigate: (key: string) => void = () => {};
  /** 设置页里的称呼 */
  @State userName: string = '';
  // v4.26：窄导航（平板竖屏）只留图标 —— 照网页端 @media(max-width:980px) 的 70px 侧栏
  @StorageLink('wb_layout') layoutMode: number = 0;
  @StorageLink('wb_width') winW: number = 0;
  private unsub: (() => void) | null = null;

  private readonly primary: RailItem[] = [
    { key: 'home', icon: 'home', label: '成长总览' } as RailItem,
    { key: 'tasks', icon: 'tasks', label: '任务面板' } as RailItem,
    { key: 'calendar', icon: 'calendar', label: '日历安排' } as RailItem,
    { key: 'notes', icon: 'note', label: '随手记' } as RailItem
  ];

  private readonly secondary: RailItem[] = [
    // v5.17：侧栏补「所有内容」——以前只有手机底部「更多」里才进得去
    { key: 'all', icon: 'doc', label: '所有内容' } as RailItem,
    { key: 'habits', icon: 'flame', label: '习惯打卡' } as RailItem,
    { key: 'projects', icon: 'folder', label: '我的项目' } as RailItem,
    { key: 'review', icon: 'undo', label: '复盘笔记' } as RailItem,
    { key: 'search', icon: 'search', label: '搜索' } as RailItem,
    { key: 'settings', icon: 'gear', label: '设置' } as RailItem
  ];

  /** v5.17：窄导航模式？窗口 ≤ 980vp（照网页端 @media(max-width:980px) 的 70px 图标栏）。
   *  以前还要求「大屏档位」，结果 640–980vp 的窗口拿到的是带文字的宽侧栏，
   *  而 981–1000vp 反而变成图标栏 ⇒ 窗口越宽侧栏越窄。 */
  private compact(): boolean {
    return this.winW > 0 && this.winW <= 980;
  }

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
    if (this.compact()) {
      // 窄导航：只留图标（网页端 980px 以下侧栏就是图标栏）
      Row() {
        SymbolGlyph(sym(it.icon))
          .fontSize(S.dialogSize)
          .fontColor([this.active === it.key ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#8FA3B6', 1)])
      }
      .width('100%')
      .height(42)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .borderRadius(S.radiusInner)
      .backgroundColor(this.active === it.key ? tk(this.pal, 'brandSoft') : '#00000000')
      .onClick(() => {
        this.onNavigate(it.key);
      })
    } else {
    Row({  space: S.space2Xl  }) {
      SymbolGlyph(sym(it.icon))
        .fontSize(S.sectionSize)
        .fontColor([this.active === it.key ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#8FA3B6', 1)])
      Text(it.label)
        .fontSize(S.bodySize)
        .fontColor(this.active === it.key ? tkInk(this.pal, 'brandDeep') : tk(this.pal, 'text'))
        .fontWeight(this.active === it.key ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .padding({  top: S.spaceXl, bottom: S.spaceXl, left: S.space2Xl, right: S.space2Xl  })
    .borderRadius(S.radiusInner)
    .backgroundColor(this.active === it.key ? tk(this.pal, 'brandSoft') : '#00000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onNavigate(it.key);
    })
    }
  }

  @Builder brand() {
    if (this.compact()) {
      // 窄导航：只留品牌方块
      Row() {
        Row() {
          SymbolGlyph(sym('grid')).fontSize(S.sectionSize).fontColor([onFill(this.pal)])
        }
        .width(34).height(34).borderRadius(S.radiusInner)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .linearGradient(brandGradient(this.pal))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else {
    Row({  space: S.spaceXl  }) {
      Row() {
        SymbolGlyph(sym('grid')).fontSize(S.sectionSize).fontColor([onFill(this.pal)])
      }
      .width(34).height(34).borderRadius(S.radiusInner)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .linearGradient(brandGradient(this.pal))
      Column({  space: S.spaceXs  }) {
        Text('小记')
          .fontSize(S.iconSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text'))
        Text('XIAOJI')
          .fontSize(S.tinySize).fontColor(tk(this.pal, 'textHint')).letterSpacing(1.6)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    }
  }

  @Builder foot() {
    if (this.compact()) {
      // 窄导航：只留头像（点它进设置）
      Row() {
        Row() {
          Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '我')
            .fontSize(S.midSize).fontWeight(FontWeight.Medium).fontColor(onFill(this.pal))
        }
        .width(30).height(30).borderRadius(S.radiusCard)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .linearGradient(brandGradient(this.pal))
        .onClick(() => {
          this.onNavigate('settings');
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({  top: S.spaceXl  })
      .border({ width: { top: 1 }, color: tk(this.pal, 'line') })
    } else {
    Row({  space: S.spaceXl  }) {
      Row() {
        Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '我')
          .fontSize(S.midSize).fontWeight(FontWeight.Medium).fontColor(onFill(this.pal))
      }
      .width(30).height(30).borderRadius(S.radiusCard)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .linearGradient(brandGradient(this.pal))
      Text(this.userName.length > 0 ? this.userName : '我')
        .fontSize(S.smallSize).fontColor(tk(this.pal, 'text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph(sym('gear'))
        .fontSize(S.iconSize)
        .fontColor([tc(this.pal, '#9BAFC0', 1)])
        .onClick(() => {
          this.onNavigate('settings');
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({  top: S.spaceXl  })
    .border({ width: { top: 1 }, color: tk(this.pal, 'line') })
    }
  }

  build() {
    Column() {
      this.brand()

      if (!this.compact()) {
        Text('安排好行动，让生活慢慢生长。')
          .fontSize(S.subSize).fontColor(tk(this.pal, 'textSub'))
          .width('100%')
          .margin({  top: S.spaceLg, bottom: S.space2Xl  })
      } else {
        Blank().height(12)
      }

      Column({  space: S.spaceXs  }) {
        ForEach(this.primary, (it: RailItem) => {
          this.navItem(it)
        }, (it: RailItem) => `rail-p-${it.key}`)
      }
      .width('100%')

      Divider()
        .color(tk(this.pal, 'line'))
        .margin({  top: S.spaceXl, bottom: S.spaceXl  })

      Column({  space: S.spaceXs  }) {
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
    .padding({  left: this.compact() ? 8 : 14, right: this.compact() ? 8 : 14, top: S.space6Xl, bottom: S.space4Xl  })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(tc(this.pal, '#FFFFFF', 0))
    .border({ width: { right: 1 }, color: tk(this.pal, 'line') })
  }
}
