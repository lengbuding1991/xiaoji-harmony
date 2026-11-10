// 用户协议与隐私政策正文页（v4.7 · 上架准备）
//
// 上架必须能在 App 里看到完整协议正文，所以正文写在这里，不依赖网络。
// 设置页 → 「隐私与协议」→ 这里；首启隐私弹窗里点《用户协议》《隐私政策》也会到这里。
import { C, onFill, S, tc, tk } from '../utils/Theme';
import { TopBar } from '../components/TopBar';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

interface Sec {
  h: string;
  p: string;
}

@Component
export struct PolicyView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tab: number = 0;
  onNavigate: (page: string) => void = () => {};

  private readonly terms: Sec[] = [
    {
      h: '一、协议的接受',
      p: '本协议是你与「小记」（以下简称「本 App」）之间关于使用本 App 所订立的协议。' +
        '在你勾选同意并点击「同意并开始使用」之前，你不能正常使用本 App。' +
        '若你不同意本协议，请点击「不同意并退出」并停止使用本 App。'
    },
    {
      h: '二、服务内容',
      p: '本 App 为一款纯本地的个人成长管理工具，提供任务面板、日历安排、记录灵感、每日习惯、' +
        '项目进度、每日复盘、数据洞察、全局搜索与提醒等功能。' +
        '本 App 为单机应用，不提供在线账号体系、不提供服务器端存储、不提供任何收费的虚拟物品。'
    },
    {
      h: '三、你的数据',
      p: '本 App 收集并存储的一切内容（包括任务、日程、记录、复盘、项目、习惯及你设置的称呼）' +
        '均只保存在你设备本地的应用沙盒数据库中，不会上传到任何服务器，也不会提供给任何第三方。' +
        '卸载本 App 或清除应用数据会一并删除这些内容，重要数据请自行通过「设置 → 复制备份」导出留存。'
    },
    {
      h: '四、提醒清单说明',
      p: '本 App 顶部的铃铛会列出「已经逾期」「今天到期」「12 小时内要做」的任务与日程，' +
        '这部分提醒完全在 App 内计算与展示，不需要任何系统权限，也不会在 App 之外弹出通知。' +
        '本 App 不申请、不使用任何系统权限。'
    },
    {
      h: '五、你的权利',
      p: '你可以随时查看、修改、删除本 App 内的全部内容；可以导出备份，也可以在「设置」中一键清空全部数据。' +
        '本 App 不申请任何系统权限，因此也不存在需要你撤回的系统授权；' +
        '你随时可以卸载本 App 以停止使用本服务。'
    },
    {
      h: '六、知识产权',
      p: '本 App 的程序、界面设计、图标与文案等知识产权归开发者所有。未经书面许可，任何人不得复制、' +
        '修改、反编译或用于商业用途。'
    },
    {
      h: '七、免责声明',
      p: '本 App 按「现状」提供，不对因设备故障、操作系统差异、数据丢失或用户误操作导致的数据损失承担责任。' +
        '请定期使用备份功能保存重要内容。'
    },
    {
      h: '八、协议的更新',
      p: '当功能或法律要求发生变化时，我们可能修订本协议并在 App 内更新本页面。' +
        '修订后的协议自本页面更新之日起生效，继续使用即视为接受。'
    },
    {
      h: '九、联系我们',
      p: '如对本协议或本 App 有疑问，可在应用市场的评价区反馈，或通过应用市场提供的开发者联系方式与我们取得联系。'
    }
  ];

  private readonly policy: Sec[] = [
    {
      h: '一、我们是谁',
      p: '「小记」是一款运行在 HarmonyOS / OpenHarmony 设备上的个人成长管理工具，' +
        '由开发者独立开发并运营，不隶属于任何第三方平台。'
    },
    {
      h: '二、我们收集哪些信息',
      p: '我们不收集你的个人信息：不收集姓名、手机号码、身份证件、通讯录、精确位置、' +
        '也不读取你的剪贴板内容用于识别。你的称呼由你自己填写，仅用于首页问候语展示，' +
        '并且只保存在本机。'
    },
    {
      h: '三、数据存储位置与期限',
      p: '你在本 App 中创建的全部内容保存在设备本地的应用沙盒数据库（relationalStore）中，' +
        '存储期限与 App 的安装周期一致。数据不会离开你的设备；卸载 App 或在系统设置中清除数据后，' +
        '相关数据将被一并删除且无法恢复。'
    },
    {
      h: '四、系统权限使用说明',
      p: '本 App 不申请任何系统权限。它不在后台运行、不读取设备标识、不读取剪贴板内容用于识别、' +
        '不访问网络、不调用系统通知或代理提醒接口；所有功能都在你打开 App 时于本机完成。'
    },
    {
      h: '五、联网与第三方',
      p: '本 App 不申请网络访问权限，不内置任何第三方 SDK、广告组件或统计 SDK，' +
        '不会与任何服务器建立连接，不上传、不共享、不出售你的任何信息。'
    },
    {
      h: '六、数据导出与删除',
      p: '你可以在「设置 → 备份与恢复」中把全部内容导出为一段纯文本（JSON）备份，' +
        '自行保存到任意位置；也可以在「设置 → 清空数据」中一次性删除全部内容。' +
        '导出的备份文件由你自行保管，我们无法访问。'
    },
    {
      h: '七、未成年人保护',
      p: '本 App 不面向未满 14 周岁的未成年人提供在线服务。若你是未成年人的监护人，' +
        '请监督其使用，并在必要时及时删除本 App 中的相关数据。'
    },
    {
      h: '八、隐私政策的更新',
      p: '当功能或法律要求发生变化时，我们可能更新本政策并在 App 内更新本页面。' +
        '本 App 的数据处理方式始终遵循「本地存储、不联网、不上传」的原则。'
    },
    {
      h: '九、联系我们',
      p: '如对本隐私政策有任何疑问，可在应用市场的评价区反馈，或通过应用市场提供的开发者联系方式与我们取得联系。'
    }
  ];

  private secs(): Sec[] {
    return this.tab === 0 ? this.terms : this.policy;
  }

  @Builder
  tabChip(label: string, idx: number) {
    Text(label)
      .fontSize(11.5)
      .fontWeight(this.tab === idx ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.tab === idx ? onFill(this.dark) : tc(this.dark, '#5E7183', 1))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(11)
      .backgroundColor(this.tab === idx ? tk(this.dark, 'brand') : tc(this.dark, '#FFFFFF', 0))
      .border({ width: 1, color: this.tab === idx ? tk(this.dark, 'brand') : tk(this.dark, 'line') })
      .onClick(() => { this.tab = idx; })
  }

  build() {
    Scroll() {
      Column() {
        TopBar({
          showBell: false,
          showSearch: false,
          showCalendar: false,
          onSearch: () => { this.onNavigate('search'); },
          onCalendar: () => { this.onNavigate('calendar'); }
        })
          .width('100%')

        Column({ space: 5 }) {
          Text('LEGAL · 协议与隐私').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
          Text('用户协议与隐私政策').fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
          Text('更新日期：2026 年 11 月 8 日').fontSize(10).fontColor(tk(this.dark, 'textSub'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14, bottom: 12 })

        Row({ space: 8 }) {
          this.tabChip('用户协议', 0)
          this.tabChip('隐私政策', 1)
        }
        .width('100%')
        .margin({ bottom: 12 })

        Column({ space: 12 }) {
          ForEach(this.secs(), (s: Sec) => {
            Column({ space: 4 }) {
              Text(s.h).fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(tk(this.dark, 'text')).width('100%')
              Text(s.p).fontSize(11).fontColor(tc(this.dark, '#5C7086', 1)).lineHeight(19).width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (s: Sec) => `sec-${s.h}`)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .borderRadius(S.radiusInner)
        .backgroundColor(tc(this.dark, '#FFFFFF', 0))
        .border({ width: 1, color: tk(this.dark, 'cardBorder') })
        .alignItems(HorizontalAlign.Start)

        Text('本 App 不联网、不收集个人信息；所有数据只存在你的设备上。')
          .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(16).width('100%')
          .margin({ top: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: S.pagePad, right: S.pagePad, top: S.pageTop, bottom: S.pageBottom })
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
