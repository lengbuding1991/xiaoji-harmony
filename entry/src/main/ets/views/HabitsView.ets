// 习惯打卡
// 对齐「个人工作台」HabitsApp.tsx：page-head → 汇总卡（今天 X/Y + 连续天数 + 最好记录）
// → 新增习惯输入框 → 习惯列表（勾选圆 + 名字 + 连续 + 本周 7 个圆点可补打卡）。
import { Store } from '../store/Store';
import { S, brandGradient, onFill, paletteList, tc, tk, tkInk } from '../utils/Theme';
import { R } from '../utils/Responsive';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { HabitView, HabitCreate, HabitUpdate } from '../api/Types';
import { Repo } from '../db/Repo';
import { TopBar } from '../components/TopBar';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { SheetFrame } from '../components/SheetFrame';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';


@Component
export struct HabitsView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_pal') pal: number = 0;
  @State tick: number = 0;
  @State habits: HabitView[] = [];
  // v4.5：ArkUI V1 只刷新「表达式里直接读过 state」的节点 ⇒ 计数进 @State
  @State kAlive: number = 0;
  @State kDoneToday: number = 0;
  @State kTodayPct: number = 0;
  @State kBestStreak: number = 0;
  @State newName: string = '';
  @State busy: boolean = false;
  @State editingId: number = -1;
  @State editName: string = '';
  // v4.13：圆点窗口改成「最近 7 天」滚动（数据源 Repo.habits() 返回的 days），
  // 必须跟「最近 7 天 N/7」用同一个窗口 —— v4.4 踩过的坑：两个窗口不同源会打架。
  @State weekDays: string[] = [];
  // v4.13：补更早的打卡（最近 30 天）
  @State showMore: boolean = false;
  // v4.26（平板竖屏）：宽屏的弹层不再用 bindSheet。
  //   bindSheet 的面板高度是平台按「内容高度」算的（平板竖屏实测只有 560vp），
  //   卡片会被裁掉底部「保存/取消」，自己画的遮罩也只能盖住面板那一块。
  //   ⇒ 宽屏改成在页面里自己铺一层遮罩 + 居中卡片（wideOverlay），窄屏仍是底部抽屉。
  @State wideOpen: boolean = false;

  /** v4.26：宽屏走页面内浮层，窄屏走 bindSheet 底部抽屉 */
  private openSheet(): void {
    if (this.wideMode()) {
      this.wideOpen = true;
      // 浮层盖住内容区时，右下角的悬浮按钮（在页面层）会浮到遮罩上面，先藏掉
      AppStorage.setOrCreate<boolean>('wb_fab_hide', true);
    } else {
      this.showMore = true;
    }
  }

  private closeSheet(): void {
    this.showMore = false;
    this.wideOpen = false;
    AppStorage.setOrCreate<boolean>('wb_fab_hide', false);
  }

  /** v4.26：宽屏时铺在页面最上层的遮罩 + 居中卡片 */
  @Builder
  wideOverlay() {
    if (this.wideMode() && this.wideOpen) {
      this.moreContent()
    }
  }

  @State moreHabitId: number = -1;
  @State moreDays: string[] = [];
  // v4.6：宽屏时弹层走「遮罩 + 居中卡片」
  @StorageLink('wb_layout') layoutMode: number = 0;
  private unsub: () => void = () => {};

  private syncStore(): void {
    this.habits = Store.I.habits;
    this.weekDays = Store.I.habitDays;
    this.recalc();
  }

  /** v4.5：汇总卡的数字全部预计算进 @State */
  private recalc(): void {
    const alive: HabitView[] = this.alive();
    this.kAlive = alive.length;
    let done: number = 0;
    let best: number = 0;
    for (const h of alive) {
      if (h.doneToday) { done += 1; }
      // v4.13：汇总卡那个「最长 N 天」胶囊改成历史最长（成就，不会归零）；
      // 当前连续天数在每一行的火苗上显示。
      if (h.bestStreak > best) { best = h.bestStreak; }
    }
    this.kDoneToday = done;
    this.kTodayPct = alive.length === 0 ? 0 : Math.round(done * 100 / alive.length);
    this.kBestStreak = best;
  }
  onNavigate: (page: string) => void = () => {};
  // v5.17：二级页返回（Index 传进来的）
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  // ── 统计 ──
  private alive(): HabitView[] {
    return this.habits.filter((h: HabitView) => h.archived === 0);
  }

  private doneToday(): number {
    let n = 0;
    for (const h of this.alive()) { if (h.doneToday) { n += 1; } }
    return n;
  }

  private todayPct(): number {
    const total: number = this.alive().length;
    return total === 0 ? 0 : Math.round(this.doneToday() * 100 / total);
  }

  private bestStreak(): number {
    let m = 0;
    for (const h of this.alive()) { if (h.streak > m) { m = h.streak; } }
    return m;
  }

  private totalStreak(): number {
    let n = 0;
    for (const h of this.alive()) { n += h.streak; }
    return n;
  }

  /** 最近 7 天（周一 → 今天），用于本周圆点 */
  private logged(h: HabitView, day: string): boolean {
    return h.logs.indexOf(day) >= 0;
  }

  private future(day: string): boolean {
    return day > D.today();
  }

  private wideMode(): boolean {
    return this.layoutMode >= 1;
  }

  // ── v4.13：补更早的打卡（最近 30 天） ──
  private openMore(h: HabitView): void {
    this.moreHabitId = h.id;
    this.moreDays = D.lastDays(30);
    this.openSheet();
  }

  private moreHabitName(): string {
    for (const h of this.habits) {
      if (h.id === this.moreHabitId) { return h.name; }
    }
    return '';
  }

  private moreLogged(day: string): boolean {
    for (const h of this.habits) {
      if (h.id === this.moreHabitId) { return h.logs.indexOf(day) >= 0; }
    }
    return false;
  }

  private async toggleMore(day: string): Promise<void> {
    if (this.future(day)) {
      toast(this.getUIContext(), '还没到那天，不能提前打卡');
      return;
    }
    const ok: boolean = await Store.I.toggleHabit(this.moreHabitId, day);
    if (!ok) {
      toast(this.getUIContext(), Store.I.lastError.length > 0 ? Store.I.lastError : '没打卡成功');
    }
  }

  private async add(): Promise<void> {
    const name: string = this.newName.trim();
    if (name.length === 0) { toast(this.getUIContext(), '先写个习惯名'); return; }
    if (name.length > 40) { toast(this.getUIContext(), '习惯名最多 40 个字'); return; }
    this.busy = true;
    const body: HabitCreate = { name: name } as HabitCreate;
    const ok: boolean = await Store.I.addHabit(body);
    this.busy = false;
    if (ok) {
      this.newName = '';
      toast(this.getUIContext(), '加好了，从今天开始');
    } else {
      toast(this.getUIContext(), Store.I.lastError.length > 0 ? Store.I.lastError : '没加上，再试一次');
    }
  }

  private async toggle(h: HabitView, day: string): Promise<void> {
    if (this.future(day)) {
      toast(this.getUIContext(), '还没到那天，不能提前打卡');
      return;
    }
    const ok: boolean = await Store.I.toggleHabit(h.id, day);
    if (!ok) {
      toast(this.getUIContext(), Store.I.lastError.length > 0 ? Store.I.lastError : '没打卡成功');
    }
  }

  /** 删除习惯：先弹自绘确认框（打卡记录会一起没） */
  private remove(h: HabitView): void {
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '删除这个习惯？', `「${h.name}」会连同它的打卡记录一起移除，删除后无法恢复。`, '删除',
      () => { this.doRemove(h); });
  }

  /** 确认之后才真的删 */
  private async doRemove(h: HabitView): Promise<void> {
    try {
      await Repo.deleteHabit(h.id);
      await Store.I.reloadHabits();
      toast(this.getUIContext(), '删掉了');
    } catch (e) {
      toast(this.getUIContext(), (e as Error).message);
    }
  }

  private async rename(h: HabitView): Promise<void> {
    const name: string = this.editName.trim();
    if (name.length === 0) { this.editingId = -1; return; }
    try {
      const body: HabitUpdate = { name: name } as HabitUpdate;
      await Repo.patchHabit(h.id, body);
      await Store.I.reloadHabits();
      this.editingId = -1;
      toast(this.getUIContext(), '改好了');
    } catch (e) {
      toast(this.getUIContext(), (e as Error).message);
    }
  }

  // ── 视图 ──
  @Builder habitRow(h: HabitView) {
    Column({  space: S.spaceLg  }) {
      Row({  space: S.spaceXl  }) {
        // 勾选圆
        // v5.15 可访问性：打卡圆原来只有 26×26 ⇒ 外层套 40×40 的透明热区，
        //   圆本身还是 26（视觉不变），手指能点到的范围变成 40×40。
        Row() {
          Row() {
            if (h.doneToday) {
              SymbolGlyph(sym('check')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'brandDeep')])
            }
          }
          .width(26).height(26).borderRadius(S.radiusInner)
          .backgroundColor(h.doneToday ? tk(this.pal, 'brandSoft') : tk(this.pal, 'card'))
          .border({ width: 1.5, color: h.doneToday ? tk(this.pal, 'study') : tk(this.pal, 'checkRing') })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .flexShrink(0)
        .onClick(() => { this.toggle(h, D.today()); })
        .accessibilityText(`打卡 ${h.name}`)

        // 名字 / 编名字
        if (this.editingId === h.id) {
          TextInput({ text: this.editName })
            .fontSize(S.midSize).height(34).layoutWeight(1)
            .placeholderFont({ size: 13 })
            .placeholderColor(tc(this.pal, '#A8B8C6', 1))
            .fontColor(tk(this.pal, 'text'))
            .caretColor(tk(this.pal, 'brand'))
            .backgroundColor(tc(this.pal, '#F7FBFE', 0)).borderRadius(S.radiusSm)
            .padding({  left: S.spaceXl, right: S.spaceXl  })
            .onChange((v: string) => { this.editName = v; })
            .onSubmit(() => { this.rename(h); })
        } else {
          Column({  space: S.spaceXs  }) {
            Text(h.name)
              .fontSize(S.midSize)
              .fontColor(tc(this.pal, '#2C4257', 1))
              .fontWeight(h.doneToday ? FontWeight.Normal : FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(h.doneToday ? '今天已经打上卡了' : '今天还没打卡')
              .fontSize(S.microSize)
              .fontColor(h.doneToday ? tkInk(this.pal, 'brandDeep') : tc(this.pal, '#A8B8C6', 1))
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => { this.toggle(h, D.today()); })
          .gesture(LongPressGesture().onAction(() => {
            this.editingId = h.id;
            this.editName = h.name;
          }))
        }

        Row({  space: S.spaceSm  }) {
          if (h.streak > 0) {
            SymbolGlyph(sym('flame')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'brand')])
            Text(`${h.streak}`).fontSize(S.labelSize).fontWeight(FontWeight.Medium).fontColor(tkInk(this.pal, 'brandDeep'))
          }
          // v5.15 可访问性：删除图标原来只有 ~20×20 ⇒ 外层套 40×40 的透明热区
          Row() {
            SymbolGlyph(sym('trash')).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#D8E4EE', 1)])
              .padding(3)
          }
          .width(40).height(40)
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .onClick(() => { this.remove(h); })
          .accessibilityText(`删除习惯 ${h.name}`)
        }
        .alignItems(VerticalAlign.Center)
        .flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 本周 7 个点（可补打卡）
      // v5.15 可访问性：每个点原来只有 18×18 ⇒ 外层套 40×40 的透明热区，点本身还是 18（视觉不变）；
      //   7 个格子平分整行宽度（每格 ≥40），「最近 7 天 x/7」和「⋯」挪到下一行，把宽度让给格子。
      Row({  space: 0  }) {
        ForEach(this.weekDays, (day: string) => {
          Row() {
            Column({  space: S.spaceXs  }) {
              Row()
                .width(18).height(18).borderRadius(S.radiusSm)
                .backgroundColor(this.logged(h, day) ? tk(this.pal, 'brand') : (this.future(day) ? tc(this.pal, '#F4F9FD', 0) : tc(this.pal, '#EDF4FA', 0)))
                .border({ width: 1, color: this.logged(h, day) ? tk(this.pal, 'brand') : tc(this.pal, '#E4EFF8', 2) })
              // v4.21：华为 UX 2.1.4.2 文字最小不得小于 8vp（这里原来是 7.5）
              Text(`${D.parse(day).getDate()}`).fontSize(S.tinySize).fontColor(tc(this.pal, '#B7C7D4', 1))
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .layoutWeight(1)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.toggle(h, day); })
          .accessibilityText(`打卡 ${h.name} ${D.parse(day).getMonth() + 1}月${D.parse(day).getDate()}日`)
        }, (day: string) => `d-${h.id}-${day}-${this.tick}`)
      }
      .width('100%')
      .padding({  left: 36  })
      .alignItems(VerticalAlign.Center)

      // 「最近 7 天 x/7」+「⋯」（补更早的打卡）
      Row({  space: S.spaceLg  }) {
        Text(`最近 7 天 ${h.weekDone}/7`).fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1)).flexShrink(0)
        Blank()
        // v4.13：「⋯」→ 补更早的打卡（最近 30 天）
        // v4.23：字符「⋯」墨迹只有 11.1x2.3vp（AGC 2.1.4.3.2 不达标），
        // 换成系统 square_grid_2x2，fs14 墨迹 12.5x11.4vp。
        // v5.15 可访问性：外层套 40×40 的透明热区，图标本身不变。
        Row() {
          SymbolGlyph(sym('more'))
            .fontSize(S.cardTitleSize)
            .fontColor([tc(this.pal, '#8FA2B3', 1)])
            .padding({  left: S.spaceMd, right: S.spaceXs  })
        }
        .width(40).height(40)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .onClick(() => { this.openMore(h); })
        .accessibilityText(`补更早的打卡 ${h.name}`)
      }
      .width('100%')
      .padding({  left: 36  })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({  left: S.spaceXl, right: S.spaceLg, top: S.spaceXl, bottom: S.spaceXl  })
    .borderRadius(S.radiusInner)
    .backgroundColor(h.doneToday ? tc(this.pal, '#F8FDFC', 0) : tk(this.pal, 'card'))
    .border({ width: 1, color: h.doneToday ? tc(this.pal, '#DFF3EF', 2) : tk(this.pal, 'cardBorder') })
    .margin({  bottom: S.spaceLg  })
    .alignItems(HorizontalAlign.Start)
  }

  /** v4.13：补更早的打卡（最近 30 天）—— 宽屏走居中弹窗，手机是底部抽屉 */
  @Builder moreBody() {
    Column({  space: S.spaceLg  }) {
      Text(`补「${this.moreHabitName()}」的打卡`)
        .fontSize(S.cardTitleSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text'))
      Text('最近 30 天。做了但忘了打卡的，点一下就补上。')
        .fontSize(S.subSize).fontColor(tk(this.pal, 'textSub'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.moreDays, (day: string) => {
          // v5.15 可访问性：补打卡格子原来只有 30 宽 ⇒ 外层套 40 宽的热区，方块本身不变
          Row() {
            Column({  space: S.spaceXs  }) {
              Row() {
                if (this.moreLogged(day)) {
                  SymbolGlyph(sym('check')).fontSize(S.cardTitleSize).fontColor([tkInk(this.pal, 'brandDeep')])
                }
              }
              .width(30).height(30).borderRadius(S.radiusCard)
              .backgroundColor(this.moreLogged(day) ? tk(this.pal, 'brandSoft')
                : (this.future(day) ? tc(this.pal, '#F4F9FD', 0) : tc(this.pal, '#EDF4FA', 0)))
              .border({ width: 1, color: this.moreLogged(day) ? tk(this.pal, 'study') : tc(this.pal, '#E4EFF8', 2) })
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              Text(`${D.parse(day).getMonth() + 1}/${D.parse(day).getDate()}`)
                .fontSize(S.tinySize).fontColor(tc(this.pal, '#B7C7D4', 1))
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width(40)
          .constraintSize({ minHeight: 40 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .margin({  right: S.spaceMd, bottom: S.spaceMd  })
          .onClick(() => { this.toggleMore(day); })
          .accessibilityText(`补打卡 ${D.parse(day).getMonth() + 1}月${D.parse(day).getDate()}日`)
        }, (day: string) => `md-${day}-${this.tick}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({  left: S.space4Xl, right: S.space4Xl, top: S.spaceMd, bottom: S.space4Xl  })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder moreContent() {
    SheetFrame({
      wide: this.wideMode(),
      onClose: () => { this.closeSheet(); this.moreHabitId = -1; },
      content: () => { this.moreBody(); }
    })
  }

  @Builder pageTop() {
    TopBar({
      backLabel: '返回',
      onBack: () => { this.onBack(); },
      showBell: false,
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  // ═══ v5.1：从「数据洞察」页搬过来的半年热力图 ═══
  // 原来那一页统计的是「每天完成几件任务」，跟习惯没关系；
  // 现在统计「每天打了几次卡」，放在习惯页下面才说得通。
  private readonly heatCell: number = 8.5;
  private readonly heatGap: number = 2.5;

  /** 最近 182 天里每天打卡了几个习惯 */
  private heatCounts(): number[] {
    const days: string[] = D.lastDays(182);
    const out: number[] = [];
    for (const day of days) {
      let n: number = 0;
      for (const h of this.habits) {
        if (h.logs.indexOf(day) >= 0) { n += 1; }
      }
      out.push(n);
    }
    return out;
  }

  /** 按周分列（周一起始），前补空；-1 表示空格子 */
  private heatWeeks(): number[][] {
    const counts: number[] = this.heatCounts();
    const days: string[] = D.lastDays(182);
    let max: number = 1;
    for (const c of counts) { if (c > max) { max = c; } }

    let lead: number = 0;
    if (days.length > 0) {
      const wd: number = D.parse(days[0]).getDay();
      lead = (wd + 6) % 7;
    }
    const flat: number[] = [];
    for (let i = 0; i < lead; i++) { flat.push(-1); }
    for (const c of counts) {
      let lv: number = 0;
      if (c > 0) {
        if (c <= max * 0.34) { lv = 1; }
        else if (c <= max * 0.67) { lv = 2; }
        else { lv = 3; }
      }
      flat.push(lv);
    }
    const weeks: number[][] = [];
    let row: number[] = [];
    for (const cell of flat) {
      row.push(cell);
      if (row.length === 7) { weeks.push(row); row = []; }
    }
    if (row.length > 0) {
      while (row.length < 7) { row.push(-1); }
      weeks.push(row);
    }
    return weeks;
  }

  private heatColor(level: number): string {
    const arr: string[] = paletteList(this.pal, 'heatSoft');
    const i: number = Math.min(Math.max(level, 0), arr.length - 1);
    return arr[i] ?? '#EDF4FA';
  }

  @Builder heatLegend() {
    Row({  space: S.spaceSm  }) {
      Text('少').fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
      ForEach([0, 1, 2, 3], (lv: number) => {
        Row().width(this.heatCell).height(this.heatCell).borderRadius(S.radiusDot)
          .backgroundColor(this.heatColor(lv))
      }, (lv: number) => `hg-${lv}-${this.pal}`)
      Text('多').fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
      Text('最近半年，每天打了几次卡').fontSize(S.tinySize).fontColor(tc(this.pal, '#A8B8C6', 1))
    }
    .alignItems(VerticalAlign.Center)
    .margin({  top: S.spaceLg  })
  }

  build() {
    Stack() {

      Scroll() {
        Column() {
          Text(`${this.tick}`).fontSize(S.hiddenSize).width(1).height(1).opacity(0)

          this.pageTop()

          // page-head
          Column({  space: S.spaceMd  }) {
            Text('HABITS · 习惯打卡').fontSize(S.tinySize).fontColor(tc(this.pal, '#9DB0C1', 1)).letterSpacing(1.6)
            Text('每天做一点，就算数。')
              .fontSize(S.sectionSize).fontWeight(FontWeight.Bold).fontColor(tk(this.pal, 'text')).letterSpacing(-0.2)
            Text('只记今天做没做，连续天数自己会数。')
              .fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({  top: S.spaceXl, bottom: S.spaceXl  })

          // 汇总卡（对齐 .hb-sum：大数字 X / Y + 中间说明与进度条 + 右侧琥珀「最长 N 天」胶囊）
          Card({ headMode: '', bodyPadTop: 15, bodyPadBottom: 15 }) {
            Row({  space: S.space4Xl  }) {
              Row({  space: S.spaceSm  }) {
                Text(`${this.kDoneToday}`)
                  .fontSize(S.heroNumberSize).fontWeight(FontWeight.Bold).fontColor(tkInk(this.pal, 'brandDeep')).letterSpacing(-0.9)
                Text(`/ ${this.kAlive}`)
                  .fontSize(S.smallSize).fontColor(tk(this.pal, 'textFaint'))
              }
              .flexShrink(0)
              .alignItems(VerticalAlign.Bottom)

              Column({  space: S.spaceMd  }) {
                Text(this.kAlive === 0
                  ? '还没有习惯'
                  : (this.kDoneToday === this.kAlive
                    ? '今天全部完成'
                    : `今天还差 ${this.kAlive - this.kDoneToday} 个`))
                  .fontSize(S.labelSize).fontColor(tk(this.pal, 'textSub'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Row() {
                  Row()
                    .height('100%')
                    .width(`${this.kTodayPct}%`)
                    .borderRadius(S.radiusPill)
                    .linearGradient({ angle: 90, colors: [[tk(this.pal, 'gradFrom'), 0], [tk(this.pal, 'work'), 1]] })
                }
                .width('100%').height(7).borderRadius(S.radiusPill).backgroundColor(tc(this.pal, '#EDF5FB', 0))
                .alignItems(VerticalAlign.Center)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Row({  space: S.spaceSm  }) {
                SymbolGlyph(sym('flame')).fontSize(S.cardTitleSize).fontColor([tc(this.pal, '#86630F', 1)])
                Text(`历史最长 ${this.kBestStreak} 天`).fontSize(S.subSize).fontColor(tc(this.pal, '#86630F', 1))
              }
              .flexShrink(0)
              .padding({  left: S.spaceXl, right: S.spaceXl, top: S.spaceMd, bottom: S.spaceMd  })
              .borderRadius(S.radiusPill)
              .backgroundColor(tc(this.pal, '#FDF4DC', 0))
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          // 新增
          Row({  space: S.spaceLg  }) {
            TextInput({ placeholder: '加一个习惯，比如：喝水、读 10 页书、11 点前睡', text: this.newName })
              .fontSize(S.bodySize).height(38).layoutWeight(1)
              .placeholderFont({ size: 12.5 })
              .placeholderColor(tc(this.pal, '#A8B8C6', 1))
              .fontColor(tk(this.pal, 'text'))
              .caretColor(tk(this.pal, 'brand'))
              .backgroundColor('#00000000').padding(0)
              .maxLength(40)
            .onChange((v: string) => { this.newName = v; })
              .onSubmit(() => { this.add(); })
            Row({  space: S.spaceSm  }) {
              SymbolGlyph(sym('plus')).fontSize(S.cardTitleSize).fontColor([onFill(this.pal)])
              Text(this.busy ? '加中…' : '添加').fontSize(S.labelSize).fontColor(onFill(this.pal))
            }
            // v5.15 可访问性：「添加」按钮原来只有 30 高 ⇒ 撑到 40（可点区域 ≥40×40）
            .height(40)
            .padding({  left: S.space2Xl, right: S.space2Xl  })
            .borderRadius(S.radiusSm)
            .linearGradient(brandGradient(this.pal))
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.add(); })
            .accessibilityText('添加习惯')
          }
          .width('100%')
          .padding({  left: S.space2Xl, right: S.spaceMd, top: S.spaceSm, bottom: S.spaceSm  })
          .borderRadius(S.radiusBtn)
          .backgroundColor(tk(this.pal, 'card'))
          .border({ width: 1, color: tk(this.pal, 'cardBorder') })
          .alignItems(VerticalAlign.Center)
          .margin({  top: S.space2Xl  })

          // 列表
          Column() {
            if (this.kAlive === 0) {
              Column({  space: S.spaceMd  }) {
                Text('先加一个最小的').fontSize(S.midSize).fontWeight(FontWeight.Medium).fontColor(tk(this.pal, 'text'))
                Text('小到不好意思不做，比如「喝一杯水」。做满一周再加下一个。')
                  .fontSize(S.labelSize).fontColor(tk(this.pal, 'textFaint'))
                  .textAlign(TextAlign.Center).lineHeight(19)
              }
              .width('100%')
              .padding({  left: S.space5Xl, right: S.space5Xl, top: 26, bottom: 26  })
              .borderRadius(S.radiusCard)
              .border({ width: 1, color: tc(this.pal, tc(this.pal, '#D8E8F4', 2), 2), style: BorderStyle.Dashed })
              .backgroundColor('rgba(255,255,255,0.55)')
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.alive(), (h: HabitView) => {
                this.habitRow(h)
              }, (h: HabitView) => `hb-${h.id}-${h.streak}-${h.doneToday}-${this.tick}`)
            }
          }
          .width('100%')
          .margin({  top: S.space2Xl  })

          // v5.1：半年热力图（原来在「数据洞察」页，那一页已经并回首页了）
          if (this.kAlive > 0) {
            Column() {
              Card({ title: '半年打卡', sub: '最近 26 周', bodyPadTop: 10 }) {
                Column({  space: 0  }) {
                  Row({ space: this.heatGap }) {
                    ForEach(this.heatWeeks(), (w: number[], wi: number) => {
                      Column({ space: this.heatGap }) {
                        ForEach(w, (lv: number, di: number) => {
                          Row()
                            .width(this.heatCell).height(this.heatCell).borderRadius(S.radiusDot)
                            .backgroundColor(lv < 0 ? '#00000000' : this.heatColor(lv))
                        }, (lv: number, di: number) => `hh-${wi}-${di}-${this.pal}`)
                      }
                    }, (w: number[], wi: number) => `hw-${wi}-${this.pal}`)
                  }
                  this.heatLegend()
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .margin({  top: S.space2Xl  })
          }

          // v5.13：原来写「点『⋯』能补最近 30 天」—— 那个「⋯」按钮 v4.23 已经换成
          //   square_grid_2x2 网格图标了，协议/说明里指的却是一个看不存在的符号。
          Text('连续天数在今天还没打卡时从昨天算起，断一天就重新数。小圆点能补最近 7 天，点右边的网格按钮能补最近 30 天。')
            .fontSize(S.tinySize)
            .fontColor(tc(this.pal, '#B7C7D4', 1))
            .width('100%')
            .margin({  top: S.spaceXl, bottom: R.bottomPad()  })
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
      .bindSheet($$this.showMore, this.moreContent(), {
        // v4.26：宽屏时给「窗口高度」这个绝对值，别写 '100%'
        //   （bindSheet 面板里百分比会被当成内容高度，面板撑不满、卡片不居中）
        // v4.26：宽屏时用 SheetSize.LARGE（面板几乎占满屏幕），窄屏还是贴底抽屉。
        //   之前写 '100%'，在 bindSheet 面板里百分比被解析成「内容高度」，
        //   面板只有 864vp（竖屏实测），卡片被顶到下半屏、遮罩也只盖住下半屏。
          height: SheetSize.FIT_CONTENT,
        dragBar: !this.wideMode(),
        showClose: false,
        backgroundColor: Color.Transparent,
        width: '100%'
      })
  

      // v4.26（平板竖屏）：宽屏的弹层在页面里自己画 —— bindSheet 的面板高度是
      //   平台按「内容高度」算的（竖屏实测只有 560vp），卡片会被裁掉底部按钮，
      //   自己画的遮罩也只能盖住面板那一块。窄屏仍然走 bindSheet 底部抽屉。
      if (this.wideMode() && this.wideOpen) {
        this.moreContent()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 自绘确认弹窗的内容（由 utils/Confirm.ets 挂到系统级弹窗层） */
  @Builder
  confirmBuilder() {
    ConfirmDialog({
      visible: true,
      title: Confirm.opt.title,
      desc: Confirm.opt.desc,
      danger: true,
      confirmText: Confirm.opt.confirmText,
      onConfirm: () => { Confirm.confirm(this.getUIContext()); },
      onCancel: () => { Confirm.cancel(this.getUIContext()); }
    })
  }
}

