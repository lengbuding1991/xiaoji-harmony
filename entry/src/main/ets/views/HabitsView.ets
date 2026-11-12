// 每日习惯
// 对齐「个人工作台」HabitsApp.tsx：page-head → 汇总卡（今天 X/Y + 连续天数 + 最好记录）
// → 新增习惯输入框 → 习惯列表（勾选圆 + 名字 + 连续 + 本周 7 个圆点可补打卡）。
import { Store } from '../store/Store';
import { C, onFill, S, tc, tk, tkInk } from '../utils/Theme';
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
  @StorageLink('wb_dark') dark: boolean = false;
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
    Column({ space: 7 }) {
      Row({ space: 10 }) {
        // 勾选圆
        Row() {
          if (h.doneToday) {
            SymbolGlyph(sym('check')).fontSize(14).fontColor([tkInk(this.dark, 'brandDeep')])
          }
        }
        .width(26).height(26).borderRadius(13)
        .backgroundColor(h.doneToday ? tk(this.dark, 'brandSoft') : tk(this.dark, 'card'))
        .border({ width: 1.5, color: h.doneToday ? tk(this.dark, 'study') : tk(this.dark, 'checkRing') })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .flexShrink(0)
        .onClick(() => { this.toggle(h, D.today()); })

        // 名字 / 编名字
        if (this.editingId === h.id) {
          TextInput({ text: this.editName })
            .fontSize(13).height(34).layoutWeight(1)
            .placeholderFont({ size: 13 })
            .placeholderColor(tc(this.dark, '#A8B8C6', 1))
            .fontColor(tk(this.dark, 'text'))
            .caretColor(tk(this.dark, 'brand'))
            .backgroundColor(tc(this.dark, '#F7FBFE', 0)).borderRadius(9)
            .padding({ left: 9, right: 9 })
            .onChange((v: string) => { this.editName = v; })
            .onSubmit(() => { this.rename(h); })
        } else {
          Column({ space: 2 }) {
            Text(h.name)
              .fontSize(13)
              .fontColor(tc(this.dark, '#2C4257', 1))
              .fontWeight(h.doneToday ? FontWeight.Normal : FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(h.doneToday ? '今天已经打上卡了' : '今天还没打卡')
              .fontSize(8.5)
              .fontColor(h.doneToday ? tkInk(this.dark, 'brandDeep') : tc(this.dark, '#A8B8C6', 1))
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

        Row({ space: 4 }) {
          if (h.streak > 0) {
            SymbolGlyph(sym('flame')).fontSize(14).fontColor([tkInk(this.dark, 'brand')])
            Text(`${h.streak}`).fontSize(11).fontWeight(FontWeight.Medium).fontColor(tkInk(this.dark, 'brandDeep'))
          }
          SymbolGlyph(sym('trash')).fontSize(14).fontColor([tc(this.dark, '#D8E4EE', 1)])
            .padding(3)
            .onClick(() => { this.remove(h); })
        }
        .alignItems(VerticalAlign.Center)
        .flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 本周 7 个点（可补打卡）
      Row({ space: 5 }) {
        ForEach(this.weekDays, (day: string) => {
          Column({ space: 2 }) {
            Row()
              .width(18).height(18).borderRadius(9)
              .backgroundColor(this.logged(h, day) ? tk(this.dark, 'brand') : (this.future(day) ? tc(this.dark, '#F4F9FD', 0) : tc(this.dark, '#EDF4FA', 0)))
              .border({ width: 1, color: this.logged(h, day) ? tk(this.dark, 'brand') : tc(this.dark, '#E4EFF8', 2) })
            // v4.21：华为 UX 2.1.4.2 文字最小不得小于 8vp（这里原来是 7.5）
            Text(`${D.parse(day).getDate()}`).fontSize(9).fontColor(tc(this.dark, '#B7C7D4', 1))
          }
          .onClick(() => { this.toggle(h, day); })
        }, (day: string) => `d-${h.id}-${day}-${this.tick}`)

        Blank()
        Text(`最近 7 天 ${h.weekDone}/7`).fontSize(9).fontColor(tc(this.dark, '#A8B8C6', 1)).flexShrink(0)
        // v4.13：「⋯」→ 补更早的打卡（最近 30 天）
        // v4.23：字符「⋯」墨迹只有 11.1x2.3vp（AGC 2.1.4.3.2 不达标），
        // 换成系统 square_grid_2x2，fs14 墨迹 12.5x11.4vp。
        SymbolGlyph(sym('more'))
          .fontSize(14)
          .fontColor([tc(this.dark, '#8FA2B3', 1)])
          .padding({ left: 6, right: 2 })
          .onClick(() => { this.openMore(h); })
      }
      .width('100%')
      .padding({ left: 36 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 10, right: 8, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor(h.doneToday ? tc(this.dark, '#F8FDFC', 0) : tk(this.dark, 'card'))
    .border({ width: 1, color: h.doneToday ? tc(this.dark, '#DFF3EF', 2) : tk(this.dark, 'cardBorder') })
    .margin({ bottom: 7 })
    .alignItems(HorizontalAlign.Start)
  }

  /** v4.13：补更早的打卡（最近 30 天）—— 宽屏走居中弹窗，手机是底部抽屉 */
  @Builder moreBody() {
    Column({ space: 8 }) {
      Text(`补「${this.moreHabitName()}」的打卡`)
        .fontSize(14).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text'))
      Text('最近 30 天。做了但忘了打卡的，点一下就补上。')
        .fontSize(10.5).fontColor(tk(this.dark, 'textSub'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.moreDays, (day: string) => {
          Column({ space: 2 }) {
            Row() {
              if (this.moreLogged(day)) {
                SymbolGlyph(sym('check')).fontSize(14).fontColor([tkInk(this.dark, 'brandDeep')])
              }
            }
            .width(30).height(30).borderRadius(15)
            .backgroundColor(this.moreLogged(day) ? tk(this.dark, 'brandSoft')
              : (this.future(day) ? tc(this.dark, '#F4F9FD', 0) : tc(this.dark, '#EDF4FA', 0)))
            .border({ width: 1, color: this.moreLogged(day) ? tk(this.dark, 'study') : tc(this.dark, '#E4EFF8', 2) })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            Text(`${D.parse(day).getMonth() + 1}/${D.parse(day).getDate()}`)
              .fontSize(9).fontColor(tc(this.dark, '#B7C7D4', 1))
          }
          .margin({ right: 6, bottom: 6 })
          .onClick(() => { this.toggleMore(day); })
        }, (day: string) => `md-${day}-${this.tick}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 16 })
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
      showBell: false,
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  build() {
    Stack() {

      Scroll() {
        Column() {
          Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

          this.pageTop()

          // page-head
          Column({ space: 5 }) {
            Text('HABITS · 每日习惯').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
            Text('每天做一点，就算数。')
              .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
            Text('只记今天做没做，连续天数自己会数。')
              .fontSize(11).fontColor(tk(this.dark, 'textSub'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 14, bottom: 14 })

          // 汇总卡（对齐 .hb-sum：大数字 X / Y + 中间说明与进度条 + 右侧琥珀「最长 N 天」胶囊）
          Card({ headMode: '', bodyPadTop: 15, bodyPadBottom: 15 }) {
            Row({ space: 16 }) {
              Row({ space: 3 }) {
                Text(`${this.kDoneToday}`)
                  .fontSize(29).fontWeight(FontWeight.Bold).fontColor(tkInk(this.dark, 'brandDeep')).letterSpacing(-0.9)
                Text(`/ ${this.kAlive}`)
                  .fontSize(12).fontColor(tk(this.dark, 'textFaint'))
              }
              .flexShrink(0)
              .alignItems(VerticalAlign.Bottom)

              Column({ space: 6 }) {
                Text(this.kAlive === 0
                  ? '还没有习惯'
                  : (this.kDoneToday === this.kAlive
                    ? '今天全部完成'
                    : `今天还差 ${this.kAlive - this.kDoneToday} 个`))
                  .fontSize(11).fontColor(tk(this.dark, 'textSub'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Row() {
                  Row()
                    .height('100%')
                    .width(`${this.kTodayPct}%`)
                    .borderRadius(99)
                    .linearGradient({ angle: 90, colors: [['#1C7C74', 0], ['#1A6499', 1]] })
                }
                .width('100%').height(7).borderRadius(99).backgroundColor(tc(this.dark, '#EDF5FB', 0))
                .alignItems(VerticalAlign.Center)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Row({ space: 4 }) {
                SymbolGlyph(sym('flame')).fontSize(14).fontColor([tc(this.dark, '#A97C1B', 1)])
                Text(`最长 ${this.kBestStreak} 天`).fontSize(10).fontColor(tc(this.dark, '#A97C1B', 1))
              }
              .flexShrink(0)
              .padding({ left: 9, right: 9, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(tc(this.dark, '#FDF4DC', 0))
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          // 新增
          Row({ space: 8 }) {
            TextInput({ placeholder: '加一个习惯，比如：喝水、读 10 页书、11 点前睡', text: this.newName })
              .fontSize(12.5).height(38).layoutWeight(1)
              .placeholderFont({ size: 12.5 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor('#00000000').padding(0)
              .maxLength(40)
            .onChange((v: string) => { this.newName = v; })
              .onSubmit(() => { this.add(); })
            Row({ space: 4 }) {
              SymbolGlyph(sym('plus')).fontSize(14).fontColor([onFill(this.dark)])
              Text(this.busy ? '加中…' : '添加').fontSize(11).fontColor(onFill(this.dark))
            }
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(9)
            .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
            .onClick(() => { this.add(); })
          }
          .width('100%')
          .padding({ left: 12, right: 6, top: 4, bottom: 4 })
          .borderRadius(11)
          .backgroundColor(tk(this.dark, 'card'))
          .border({ width: 1, color: tk(this.dark, 'cardBorder') })
          .alignItems(VerticalAlign.Center)
          .margin({ top: 12 })

          // 列表
          Column() {
            if (this.kAlive === 0) {
              Column({ space: 6 }) {
                Text('先加一个最小的').fontSize(13).fontWeight(FontWeight.Medium).fontColor(tk(this.dark, 'text'))
                Text('小到不好意思不做，比如「喝一杯水」。做满一周再加下一个。')
                  .fontSize(11).fontColor(tk(this.dark, 'textFaint'))
                  .textAlign(TextAlign.Center).lineHeight(19)
              }
              .width('100%')
              .padding({ left: 18, right: 18, top: 26, bottom: 26 })
              .borderRadius(18)
              .border({ width: 1, color: tc(this.dark, tc(this.dark, '#D8E8F4', 2), 2), style: BorderStyle.Dashed })
              .backgroundColor(this.dark ? 'rgba(24,34,46,0.6)' : 'rgba(255,255,255,0.55)')
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.alive(), (h: HabitView) => {
                this.habitRow(h)
              }, (h: HabitView) => `hb-${h.id}-${h.streak}-${h.doneToday}-${this.tick}`)
            }
          }
          .width('100%')
          .margin({ top: 12 })

          Text('连续天数在今天还没打卡时从昨天算起，断一天就重新数。小圆点能补最近 7 天，点「⋯」能补最近 30 天。')
            .fontSize(9)
            .fontColor(tc(this.dark, '#B7C7D4', 1))
            .width('100%')
            .margin({ top: 10, bottom: S.pageBottom })
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

