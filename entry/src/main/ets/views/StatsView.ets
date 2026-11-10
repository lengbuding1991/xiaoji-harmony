// 数据洞察
// 对齐「个人工作台」StatsApp.tsx：5 个 KPI → 近半年坚持（热力图）→ 最近 30 天柱线
// → 最近 7 天完成（大柱）→ 各条线的推进 → 项目推进 → 最近完成的 → 常用标签。
import { Store, AreaStat, isConsumedRepeat } from '../store/Store';
import { C, S, areaColor, areaLabel, tk, tc } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { Kpi } from '../components/Widgets';
import { sym } from '../components/Icon';
import { Task, Project, Note, Review } from '../api/Types';
import { TopBar } from '../components/TopBar';
import { Repo } from '../db/Repo';
import { pasteboard } from '@kit.BasicServicesKit';
import { toast } from '../utils/Toast';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

interface TagStat { tag: string; n: number }
interface HeatCell { level: number; blank: boolean }

@Component
export struct StatsView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tick: number = 0;
  @State tasks: Task[] = [];
  // v4.5：ArkUI V1 只刷新「表达式里直接读过 state」的节点 ⇒ 计数进 @State
  @State kTotal: number = 0;
  @State kDone: number = 0;
  @State kRate: number = 0;
  @State kActiveDays: number = 0;
  @State kSeriesSum: number = 0;
  @State kStreak: number = 0;
  @State notes: Note[] = [];
  @State reviews: Review[] = [];
  @State projects: Project[] = [];
  private unsub: () => void = () => {};

  private syncStore(): void {
    this.areaStats = Store.I.areaStats();
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.reviews = Store.I.reviews;
    this.projects = Store.I.projects;
    this.recalc();
  }

  /** v4.5：顶部 KPI 的数字全部预计算进 @State */
  private recalc(): void {
    this.kTotal = this.total();
    this.kDone = this.doneCount();
    this.kRate = this.rate();
    this.kActiveDays = this.activeDays();
    this.kSeriesSum = this.seriesSum();
    this.kStreak = Store.I.activeStreak();
  }
  onNavigate: (page: string) => void = () => {};

  // v4.4：热力图 26 周 × 10px + 间隙 = 335px，比可用宽度 306px 宽
  // ⇒ 最近两三周被裁掉了。格子缩到 8.5 就正好放得下。
  private readonly cell: number = 8.5;
  private readonly gapV: number = 2.5;
  // v4.4：ArkUI V1 只刷新「表达式里直接读过 state」的节点 ⇒ 派生值进 @State
  @State areaStats: AreaStat[] = [];

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  // ── 统计口径（与工作台一致）──
  private total(): number { return this.tasks.length; }

  private doneCount(): number {
    let n = 0;
    for (const t of this.tasks) { if (t.status === 'done') { n += 1; } }
    return n;
  }

  private rate(): number {
    const total: number = this.total();
    return total === 0 ? 0 : Math.round(this.doneCount() * 100 / total);
  }

  private activeDays(): number {
    const set: string[] = [];
    for (const t of this.tasks) {
      if (t.status !== 'done' || t.done_at === null) { continue; }
      const day: string = D.dateOf(t.done_at);
      if (set.indexOf(day) < 0) { set.push(day); }
    }
    return set.length;
  }

  private weekSeries(): number[] {
    const days: string[] = D.lastDays(7);
    const out: number[] = [];
    for (const day of days) {
      let n = 0;
      for (const t of this.tasks) {
        // v4.12：重复任务做完的「原件」不计入统计
        if (t.status === 'done' && !isConsumedRepeat(t) && t.done_at !== null && D.dateOf(t.done_at) === day) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  private weekLabels(): string[] {
    const days: string[] = D.lastDays(7);
    const out: string[] = [];
    // v4.4：显示星期几（周一…），比 MM-DD 好认
    for (const d of days) { out.push(D.weekdayOf(d)); }
    return out;
  }

  /** 标签精确匹配：把标签串拆成一个个标签，看有没有完全相等的 */
  private hasTag(raw: string, tag: string): boolean {
    const parts: string[] = raw.split(/[,，、\s]+/);
    for (const p of parts) {
      if (p === tag) { return true; }
    }
    return false;
  }

  private monthSeries(): number[] {
    const days: string[] = D.lastDays(30);
    const out: number[] = [];
    for (const day of days) {
      let n = 0;
      for (const t of this.tasks) {
        // v4.12：重复任务做完的「原件」不计入统计
        if (t.status === 'done' && !isConsumedRepeat(t) && t.done_at !== null && D.dateOf(t.done_at) === day) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  private seriesSum(): number {
    let n = 0;
    for (const v of this.weekSeries()) { n += v; }
    return n;
  }

  /** 182 天：每天的完成件数（0–4+） */
  private heatCounts(): number[] {
    const days: string[] = D.lastDays(182);
    const out: number[] = [];
    for (const day of days) {
      let n = 0;
      for (const t of this.tasks) {
        // v4.12：重复任务做完的「原件」不计入统计
        if (t.status === 'done' && !isConsumedRepeat(t) && t.done_at !== null && D.dateOf(t.done_at) === day) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  /** 按周分列（周一起始），前补空 —— 与工作台 heatCells 同口径 */
  private heatWeeks(): HeatCell[][] {
    const counts: number[] = this.heatCounts();
    const days: string[] = D.lastDays(182);
    let max = 1;
    for (const c of counts) { if (c > max) { max = c; } }

    // 第一格是星期几（周一=0）
    let lead = 0;
    if (days.length > 0) {
      const wd: number = D.dateOf(days[0]).length > 0 ? D.parse(days[0]).getDay() : 0;
      lead = (wd + 6) % 7;
    }

    const flat: HeatCell[] = [];
    for (let i = 0; i < lead; i++) {
      flat.push({ level: 0, blank: true } as HeatCell);
    }
    for (const c of counts) {
      let lv = 0;
      if (c > 0) {
        if (c <= max * 0.34) { lv = 1; }
        else if (c <= max * 0.67) { lv = 2; }
        else { lv = 3; }
      }
      flat.push({ level: lv, blank: false } as HeatCell);
    }

    const weeks: HeatCell[][] = [];
    let row: HeatCell[] = [];
    for (const cell of flat) {
      row.push(cell);
      if (row.length === 7) {
        weeks.push(row);
        row = [];
      }
    }
    if (row.length > 0) {
      while (row.length < 7) { row.push({ level: 0, blank: true } as HeatCell); }
      weeks.push(row);
    }
    return weeks;
  }

  private heatColor(level: number): string {
    switch (level) {
      case 0: return '#EDF4FA';
      case 1: return '#BEE7E1';
      case 2: return '#6FD0C2';
      default: return '#2E9E92';
    }
  }

  private projectStats(): Project[] {
    const out: Project[] = [];
    for (const p of this.projects) {
      if (p.total > 0) { out.push(p); }
    }
    return out;
  }

  private recentDone(): Task[] {
    const list: Task[] = this.tasks.filter((t: Task) => t.status === 'done' && !isConsumedRepeat(t) && t.done_at !== null);
    // v4.4：先把全部排好再取前 6 条 —— 以前是先 slice(0,6) 再排，
    // 结果拿到的是「表里前 6 条里最晚的」，不是「全局最近完成的 6 条」。
    const arr: Task[] = list.slice(0);
    // 按 done_at 倒序（冒泡，避免 sort 比较器在 ArkTS 里的写法风险）
    for (let i = 0; i < arr.length; i++) {
      for (let j = i + 1; j < arr.length; j++) {
        let a: string = '';
        let b: string = '';
        const ia: string | null = arr[i].done_at;
        const ib: string | null = arr[j].done_at;
        if (ia !== null) { a = ia; }
        if (ib !== null) { b = ib; }
        if (b > a) {
          const tmp: Task = arr[i];
          arr[i] = arr[j];
          arr[j] = tmp;
        }
      }
    }
    return arr.slice(0, 6);
  }

  private tagStats(): TagStat[] {
    const tags: string[] = [];
    for (const n of this.notes) {
      if (n.tags === null || n.tags.length === 0) { continue; }
      const parts: string[] = n.tags.split(',');
      for (const p of parts) {
        const t: string = p.trim();
        if (t.length > 0 && tags.indexOf(t) < 0) { tags.push(t); }
      }
    }
    const out: TagStat[] = [];
    for (const t of tags) {
      let n = 0;
      for (const note of this.notes) {
        // v4.4：按标签精确计数 —— 以前用 indexOf 子串匹配，
        // 「工作」会把「工作台」也算进去。
        if (note.tags !== null && this.hasTag(note.tags, t)) { n += 1; }
      }
      out.push({ tag: t, n: n } as TagStat);
    }
    for (let i = 0; i < out.length; i++) {
      for (let j = i + 1; j < out.length; j++) {
        if (out[j].n > out[i].n) {
          const tmp: TagStat = out[i];
          out[i] = out[j];
          out[j] = tmp;
        }
      }
    }
    return out.slice(0, 10);
  }

  private thisMonthNotes(): number {
    const month: string = D.today().slice(0, 7);
    let n = 0;
    for (const note of this.notes) {
      if (D.dateOf(note.created_at).slice(0, 7) === month) { n += 1; }
    }
    return n;
  }

  // ── 视图 ──
  @Builder bigBar(v: number, max: number, label: string, hi: boolean) {
    Column({ space: 5 }) {
      Text(v > 0 ? `${v}` : '').fontSize(8).fontColor(tc(this.dark, '#8FA2B3', 1)).height(11)
      Column() {
        Row()
          .width('100%')
          .height(`${Math.max(4, v / max * 100)}%`)
          .borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 3, bottomRight: 3 })
          .linearGradient({
            angle: 180,
            colors: hi ? [['#7FDCCF', 0], ['#CFF2EA', 1]] : [['#BFEAF8', 0], ['#E4F4FC', 1]]
          })
          .opacity(v === 0 ? 0.35 : 1)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .constraintSize({ maxWidth: 46 })
      Text(label).fontSize(8).fontColor(tc(this.dark, '#A8B8C6', 1))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder heatLine(label: string) {
    Row({ space: 4 }) {
      Text('少').fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
      ForEach([0, 1, 2, 3], (lv: number) => {
        Row().width(this.cell).height(this.cell).borderRadius(2.5)
          .backgroundColor(this.heatColor(lv))
      }, (lv: number) => `lg-${lv}`)
      Text('多').fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
      Text(label).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
    }
    .alignItems(VerticalAlign.Center)
    .margin({ top: 8 })
  }

  @Builder pageTop() {
    TopBar({
      primaryText: '',
      secondaryText: '导出 JSON',
      showBell: false,
      onSecondary: () => { this.exportJson(); },
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  /** v4.0：直接从本地库导出 JSON（不联网），复制到剪贴板方便带走 */
  private async exportJson(): Promise<void> {
    try {
      const text: string = await Repo.exportJson();
      const pb = pasteboard.getSystemPasteboard();
      await pb.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      toast(this.getUIContext(), `已复制 ${Math.round(text.length / 1024)}KB 备份到剪贴板`);
    } catch (e) {
      toast(this.getUIContext(), (e as Error).message);
    }
  }

  build() {
    Scroll() {
      Column() {
        Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

        this.pageTop()

        // page-head
        Column({ space: 5 }) {
          Text('DATA · 数据洞察').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
          Text('看清楚，再往前走。')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
          Text('只统计本地数据，不上传云端。').fontSize(11).fontColor(tk(this.dark, 'textSub'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14, bottom: 14 })

        // 5 个 KPI（手机端 2 + 2 + 1）
        Row({ space: 8 }) {
          Column() {
            Kpi({
              label: '全部任务', icon: 'tasks', iconBg: '#E8F2FC', iconFg: '#276AA4',
              value: `${this.kTotal}`, unit: '件',
              sub: `其中 ${this.kDone} 件已完成`, pct: this.kRate
            })
          }.layoutWeight(1)
          Column() {
            Kpi({
              label: '完成率', icon: 'checkCircle', iconBg: '#E3F8F2', iconFg: '#267261',
              value: `${this.kRate}`, unit: '%',
              sub: '全部任务口径', pct: this.rate()
            })
          }.layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: 8 }) {
          Column() {
            Kpi({
              label: '记录', icon: 'note', iconBg: '#FCEAF2', iconFg: '#AA4071',
              value: `${this.notes.length}`, unit: '条',
              sub: `${this.reviews.length} 篇复盘`, pct: Math.min(100, this.notes.length * 4)
            })
          }.layoutWeight(1)
          Column() {
            Kpi({
              label: '活跃日', icon: 'calendar', iconBg: '#FDF4DC', iconFg: '#876312',
              value: `${this.kActiveDays}`, unit: '天',
              sub: '有完成任务的天', pct: Math.min(100, this.activeDays() * 8)
            })
          }.layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: 8 })

        Column() {
          Kpi({
            label: '近 7 天完成', icon: 'star', iconBg: '#F1ECFE', iconFg: '#6B4FD0',
            value: `${this.kSeriesSum}`, unit: '件',
            sub: `日均 ${(this.seriesSum() / 7).toFixed(1)} 件`,
            pct: Math.min(100, this.seriesSum() / 14 * 100)
          })
        }
        .width('100%')
        .margin({ top: 8 })

        // 近半年坚持（热力图）
        Column() {
          Card({ title: '近半年坚持', sub: `连续 ${this.kStreak} 天 · 共 ${this.kActiveDays} 天有产出`, bodyPadTop: 10 }) {
            Column({ space: 0 }) {
              Row({ space: this.gapV }) {
                ForEach(this.heatWeeks(), (w: HeatCell[], wi: number) => {
                  Column({ space: this.gapV }) {
                    ForEach(w, (c: HeatCell, di: number) => {
                      Row()
                        .width(this.cell).height(this.cell).borderRadius(2.5)
                        .backgroundColor(c.blank ? '#00000000' : this.heatColor(c.level))
                    }, (c: HeatCell, di: number) => `h-${wi}-${di}`)
                  }
                }, (w: HeatCell[], wi: number) => `w-${wi}`)
              }
              this.heatLine('')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 最近 30 天
        Column() {
          Card({ title: '最近 30 天', sub: '每天的完成件数', bodyPadTop: 10 }) {
            Column({ space: 4 }) {
              Row({ space: 2 }) {
                ForEach(this.monthSeries(), (v: number, i: number) => {
                  Column() {
                    Row()
                      .width('100%')
                      .height(`${Math.max(3, v / this.monthMax() * 100)}%`)
                      .borderRadius({ topLeft: 2, topRight: 2 })
                      .linearGradient({ angle: 180, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
                      .opacity(v === 0 ? 0.22 : 1)
                  }
                  .layoutWeight(1)
                  .height('100%')
                  .justifyContent(FlexAlign.End)
                }, (v: number, i: number) => `m30-${i}-${v}`)
              }
              .width('100%').height(64).alignItems(VerticalAlign.Bottom)

              Row() {
                Text(D.slashMd(D.parse(D.lastDays(30)[0]))).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
                Blank()
                Text(D.slashMd(new Date())).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1))
              }
              .width('100%')
            }
            .width('100%')
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 最近 7 天完成
        Column() {
          Card({ title: '最近 7 天完成的任务', sub: '按完成日统计', bodyPadTop: 10 }) {
            Row({ space: 6 }) {
              ForEach(this.weekSeries(), (v: number, i: number) => {
                Column() {
                  this.bigBar(v, this.weekMax(), this.weekLabels()[i], v === this.weekMax() && v > 0)
                }
                .layoutWeight(1)
                .height(150)
              }, (v: number, i: number) => `w7-${i}-${v}`)
            }
            .width('100%').height(150).alignItems(VerticalAlign.Bottom)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 各条线的推进
        Column() {
          Card({ title: '各条线的推进', bodyPadTop: 8 }) {
            Column({ space: 0 }) {
              // v4.4：画的是完成率（done/total），不是任务总数
              ForEach(this.areaStats, (a: AreaStat, i: number) => {
                Row({ space: 10 }) {
                  Text(a.label).fontSize(11).fontColor(tc(this.dark, '#5E7183', 1)).width(48)
                  Row() {
                    Row()
                      .height('100%')
                      .width(`${a.pct}%`)
                      .borderRadius(99)
                      .backgroundColor(a.color)
                  }
                  .layoutWeight(1).height(7).borderRadius(99).backgroundColor(tc(this.dark, '#EEF5FA', 0))
                  .alignItems(VerticalAlign.Center)
                  Text(`${a.done}/${a.total} · ${a.pct}%`)
                    .fontSize(9).fontColor(tc(this.dark, '#8FA2B3', 1)).width(72).textAlign(TextAlign.End).flexShrink(0)
                }
                .width('100%')
                .padding({ top: 9, bottom: 9 })
                .border({ width: { bottom: 1 }, color: tc(this.dark, '#F2F7FB', 2) })
                .alignItems(VerticalAlign.Center)
              }, (a: AreaStat, i: number) => `as-${i}-${a.pct}-${this.tick}`)
            }
            .width('100%')
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 项目推进
        if (this.projectStats().length > 0) {
          Column() {
            Card({ title: '项目推进', sub: '按完成比例', headMode: 'link', headText: '项目进度 →', onHead: () => { this.onNavigate('projects'); }, bodyPadTop: 8 }) {
              Column({ space: 0 }) {
                ForEach(this.projectStats(), (p: Project) => {
                  Row({ space: 9 }) {
                    Row().width(8).height(8).borderRadius(3).backgroundColor(p.color).flexShrink(0)
                    Text(p.name).fontSize(11).fontColor(tc(this.dark, '#3A4D5F', 1))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width(88)
                    Row() {
                      Row()
                        .height('100%')
                        .width(`${p.total === 0 ? 0 : Math.round(p.done * 100 / p.total)}%`)
                        .borderRadius(99)
                        .backgroundColor(p.color)
                    }
                    .layoutWeight(1).height(7).borderRadius(99).backgroundColor(tc(this.dark, '#EEF5FA', 0))
                    .alignItems(VerticalAlign.Center)
                    Text(`${p.done}/${p.total} · ${p.total === 0 ? 0 : Math.round(p.done * 100 / p.total)}%`)
                      .fontSize(9).fontColor(tc(this.dark, '#8FA2B3', 1)).width(76)
                      .textAlign(TextAlign.End).flexShrink(0)
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                  .border({ width: { bottom: 1 }, color: '#F2F7FB' })
                  .alignItems(VerticalAlign.Center)
                }, (p: Project) => `ps-${p.id}-${p.done}-${this.tick}`)
              }
              .width('100%')
            }
          }
          .width('100%')
          .margin({ top: 12 })
        }

        // 最近完成的
        Column() {
          Card({ title: '最近完成的', sub: '按完成时间倒序', headMode: 'link', headText: '任务面板 →', onHead: () => { this.onNavigate('tasks'); }, bodyPadTop: 8 }) {
            Column({ space: 0 }) {
              if (this.recentDone().length === 0) {
                Text('还没有完成的任务。').fontSize(10).fontColor(tc(this.dark, '#C6D4E0', 1))
                  .width('100%').textAlign(TextAlign.Center).padding({ top: 18, bottom: 18 })
              } else {
                ForEach(this.recentDone(), (t: Task) => {
                  Row({ space: 8 }) {
                    Row().width(7).height(7).borderRadius(4)
                      .backgroundColor(areaColor(this.dark, t.area)).flexShrink(0)
                    Text(t.title).fontSize(11).fontColor(tc(this.dark, '#4E6579', 1))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    Text(areaLabel(t.area)).fontSize(8.5).fontColor(tc(this.dark, '#A8B8C6', 1)).flexShrink(0)
                    Text(t.done_at !== null ? D.slashMd(D.parse(t.done_at)) : '')
                      .fontSize(9).fontColor(tc(this.dark, '#B6C8D6', 1)).flexShrink(0)
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                  .border({ width: { bottom: 1 }, color: '#F2F7FB' })
                  .alignItems(VerticalAlign.Center)
                }, (t: Task) => `rd-${t.id}-${this.tick}`)
              }
            }
            .width('100%')
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 常用标签
        Column() {
          Card({ title: '常用标签', sub: '按记录数', bodyPadTop: 8 }) {
            Column({ space: 8 }) {
              if (this.tagStats().length === 0) {
                Text('给记录打标签后，这里会显示你的常用主题。')
                  .fontSize(10).fontColor(tc(this.dark, '#C6D4E0', 1))
                  .width('100%').textAlign(TextAlign.Center).padding({ top: 14, bottom: 14 })
              } else {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.tagStats(), (t: TagStat) => {
                    Row({ space: 5 }) {
                      Text(t.tag).fontSize(10.5).fontColor(tc(this.dark, '#3D7BA6', 1))
                      Text(`${t.n}`).fontSize(9).fontColor(tc(this.dark, '#8FA2B3', 1))
                    }
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(999)
                    .backgroundColor(tc(this.dark, '#E9F3FB', 0))
                    .margin({ right: 6, bottom: 6 })
                  }, (t: TagStat) => `tg-${t.tag}`)
                }
                .width('100%')
              }
            }
            .width('100%')
          }
        }
        .width('100%')
        .margin({ top: 12, bottom: S.pageBottom })
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

  private weekMax(): number {
    let m = 1;
    for (const v of this.weekSeries()) { if (v > m) { m = v; } }
    return m;
  }

  private monthMax(): number {
    let m = 1;
    for (const v of this.monthSeries()) { if (v > m) { m = v; } }
    return m;
  }
}
