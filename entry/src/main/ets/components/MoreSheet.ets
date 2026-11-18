/**
 * MoreSheet —— 手机端「更多」弹层。
 *
 * v5.17 改版（用户：「更多页面的字体布局有点丑」）：
 *   旧版 5 个功能用 `Flex(wrap)` + `width('33.33%')` 排成 3 + 2，
 *   右下角永远缺一格；标签字号 10.5 偏小偏淡；「设置」单独一行还带条分隔线，整块看着是「歪」的。
 *   现在：6 个入口统一成 **3 列 × 2 行** 的方阵（设置排在最后一格），
 *   每格等宽等高、行行对齐；标签字号提到 12.5、颜色换成主题的次要文字色；
 *   关闭按钮补 40vp 热区。
 *
 * 颜色与尺寸一律走 utils/Theme.ets 的 token（tk / tkInk / class S），不写裸 hex 与裸数字。
 */
import { S, sheetShadowUp, tc, tk, tkInk } from '../utils/Theme';
import { sym } from './Icon';

interface MoreEntry {
  key: string;
  icon: string;
  label: string;
}

// v5.1：名字改直白（「每日习惯」→「习惯打卡」、「项目进度」→「我的项目」、
//   「每日复盘」→「复盘笔记」、「全局搜索」→「搜索」、「全部内容」→「所有内容」），
//   并删掉「数据洞察」——那一页的统计已经回到首页，再留一个入口就是让人多点一次。
// v5.17：补上「所有内容」（侧栏同期补的），并把「设置」排进宫格最后一格 ⇒ 3 列 × 2 行。
const ENTRIES: MoreEntry[] = [
  { key: 'habits', icon: 'flame', label: '习惯打卡' },
  { key: 'projects', icon: 'folder', label: '我的项目' },
  { key: 'review', icon: 'undo', label: '复盘笔记' },
  { key: 'search', icon: 'search', label: '搜索' },
  { key: 'all', icon: 'doc', label: '所有内容' },
  { key: 'settings', icon: 'gear', label: '设置' }
];

/** 每行放几个 —— 6 个入口正好 3 列 × 2 行 */
const PER_ROW: number = 3;

@Component
export struct MoreSheet {
  // 配色索引（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @Prop activeKey: string = '';
  onNavigate: (key: string) => void = () => {
  };
  onClose: () => void = () => {
  };

  /** 这一格的文字色：选中用品牌深色，其余用主题的次要文字色 */
  private labelColor(key: string): string {
    return this.activeKey === key ? tkInk(this.pal, 'brandDeep') : tk(this.pal, 'textSub');
  }

  /** 这一格的底色：选中用品牌浅底，其余用主题的浅填充 */
  private cellBg(key: string): string {
    return this.activeKey === key ? tk(this.pal, 'brandSoft') : tk(this.pal, 'soft');
  }

  @Builder
  entryCell(e: MoreEntry) {
    Column({  space: S.spaceMd  }) {
      SymbolGlyph(sym(e.icon))
        .fontSize(S.heroIconSize)
        .fontColor([this.labelColor(e.key)])
      Text(e.label)
        .fontSize(S.bodySize)
        .fontColor(this.labelColor(e.key))
        .fontWeight(this.activeKey === e.key ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({  top: S.space2Xl, bottom: S.space2Xl, left: S.spaceSm, right: S.spaceSm  })
    .borderRadius(S.radiusInner)
    .backgroundColor(this.cellBg(e.key))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onNavigate(e.key);
    })
  }

  build() {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('rgba(23,52,80,0.30)')
        .onClick(() => {
          this.onClose();
        })

      Column({  space: 0  }) {
        // 标题行：左标题，右关闭（40vp 热区，视觉仍是 28 的小圆块）
        Row() {
          Text('全部功能')
            .fontSize(S.cardTitleSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(tk(this.pal, 'text'))
          Blank()
          Stack() {
            Row() {
              SymbolGlyph(sym('close'))
                .fontSize(S.bodySize)
                .fontColor([tc(this.pal, '#8FA2B3', 1)])
            }
            .width(28)
            .height(28)
            .borderRadius(S.radiusInner)
            .backgroundColor(tc(this.pal, '#F2F7FB', 0))
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
          .width(40)
          .height(40)
          .onClick(() => {
            this.onClose();
          })
        }
        .width('100%')
        .margin({  bottom: S.space3Xl  })
        .alignItems(VerticalAlign.Center)

        // 宫格：3 列 × 2 行。每行用 Row + layoutWeight(1) 等分 ⇒ 行列全部对齐，不会缺角。
        Row({ space: S.spaceLg }) {
          ForEach(ENTRIES.slice(0, PER_ROW), (e: MoreEntry) => {
            this.entryCell(e)
          }, (e: MoreEntry) => `more-a-${e.key}`)
        }
        .width('100%')
        .margin({  bottom: S.spaceLg  })

        Row({ space: S.spaceLg }) {
          ForEach(ENTRIES.slice(PER_ROW, ENTRIES.length), (e: MoreEntry) => {
            this.entryCell(e)
          }, (e: MoreEntry) => `more-b-${e.key}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding({  left: S.space4Xl, right: S.space4Xl, top: S.space4Xl, bottom: S.space6Xl  })
      .backgroundColor(tk(this.pal, 'card'))
      .borderRadius({ topLeft: S.radiusSheet, topRight: S.radiusSheet })
      .shadow(sheetShadowUp(this.pal))
    }
    .width('100%')
    .height('100%')
  }
}
