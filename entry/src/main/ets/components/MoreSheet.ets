/**
 * MoreSheet —— 手机端「更多」弹层，逐项对齐个人工作台 components/Sidebar.tsx 的 .m-more。
 *
 * .m-more-mask  rgba(23,52,80,.3)，底部对齐
 * .m-more       白卡，radius 22 22 0 0，padding 16 16 (20+safe)
 * .m-more-head  「全部功能」14px #2C4257 + 28×28 圆 #F2F7FB 关闭按钮
 * .m-more-grid  3 列 gap 8；每项竖向居中 gap 7，padding 14 6，radius 14，
 *               底 #F8FBFE，字 #5C7086 10.5px，图标 20×20；选中 --acc-soft/--acc-d
 * .m-more-out   全宽 margin-top 12，padding 11，白底 --line 边，radius 12，
 *               v4.0：离线版没有「退出登录」，弹层只留功能入口
 */
import { C, S, tc, tk, tkInk } from '../utils/Theme';
import { sym } from './Icon';

interface MoreEntry {
  key: string;
  icon: string;
  label: string;
}

const ENTRIES: MoreEntry[] = [
  { key: 'all', icon: 'doc', label: '全部内容' },
  { key: 'habits', icon: 'flame', label: '每日习惯' },
  { key: 'projects', icon: 'folder', label: '项目进度' },
  { key: 'review', icon: 'undo', label: '每日复盘' },
  // v4.7：AI 助手入口删掉了（views/AiView.ets 一起清掉，是进不去的死页面）。
  // db/LocalAI.ets 保留 —— 每日复盘的「AI 起稿」本地规则还在用它（入口先隐藏）。
  { key: 'stats', icon: 'grid', label: '数据洞察' },
  { key: 'search', icon: 'search', label: '全局搜索' },
  { key: 'settings', icon: 'gear', label: '设置' }
];

@Component
export struct MoreSheet {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop activeKey: string = '';
  onNavigate: (key: string) => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('rgba(23,52,80,0.30)')
        .onClick(() => {
          this.onClose();
        })

      Column({ space: 0 }) {
        // head
        Row() {
          Text('全部功能')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(tc(this.dark, '#2C4257', 1))
          Blank()
          Row() {
            SymbolGlyph(sym('close'))
              .fontSize(14)
              .fontColor([tc(this.dark, '#8FA2B3', 1)])
          }
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor(tc(this.dark, '#F2F7FB', 0))
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .margin({ bottom: 14 })
        .alignItems(VerticalAlign.Center)

        // 3 列宫格
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(ENTRIES, (e: MoreEntry) => {
            Column({ space: 7 }) {
              SymbolGlyph(sym(e.icon))
                .fontSize(20)
                .fontColor([this.activeKey === e.key ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#5C7086', 1)])
              Text(e.label)
                .fontSize(10.5)
                .fontColor(this.activeKey === e.key ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#5C7086', 1))
                .fontWeight(this.activeKey === e.key ? FontWeight.Medium : FontWeight.Normal)
                .maxLines(1)
            }
            .width('33.33%')
            .padding({ top: 14, bottom: 14, left: 6, right: 6 })
            .margin({ bottom: 8 })
            .borderRadius(14)
            .backgroundColor(this.activeKey === e.key ? tk(this.dark, 'brandSoft') : tc(this.dark, '#F8FBFE', 0))
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onNavigate(e.key);
            })
          }, (e: MoreEntry) => `more-${e.key}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 26 })
      .backgroundColor(tk(this.dark, 'card'))
      .borderRadius({ topLeft: 22, topRight: 22 })
      .shadow({ radius: 40, color: 'rgba(23,52,80,0.18)', offsetX: 0, offsetY: -12 })
    }
    .width('100%')
    .height('100%')
  }
}
