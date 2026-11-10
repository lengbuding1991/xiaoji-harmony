// 每日复盘
// 对齐「个人工作台」ReviewApp.tsx：日/周切换 → 三个问题（今天做成什么 / 哪里卡住 /
// 明天最重要的一件事）+ 一句话总结 → 存成任务 / 保存；右侧历史列表 + 本周统计。
// v4.3：AI 起稿入口已隐藏（等做数据线上版再开），本地起稿逻辑仍在 db/LocalAI.ets。
import { Store } from '../store/Store';
import { C, onFill, S, tc, tk, tkInk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { Chip } from '../components/Widgets';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { Repo } from '../db/Repo';
import { LocalAI, ReviewDraft } from '../db/LocalAI';
import { Review, ReviewSave, TaskCreate, Task, Note } from '../api/Types';
import { TopBar } from '../components/TopBar';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

interface ReviewId { id: number }

interface AiReviewReq {
  action: string;
  date: string;
  type: string;
}

interface AiReviewResp {
  did?: string;
  stuck?: string;
  tomorrow?: string;
  error?: string;
}

@Component
export struct ReviewView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tick: number = 0;
  @State reviews: Review[] = [];
  // v4.5：ArkUI V1 只刷新「表达式里直接读过 state」的节点 ⇒ 计数进 @State
  @State kWeekDone: number = 0;
  @State kWeekNotes: number = 0;
  @State kHistory: number = 0;
  @State tasks: Task[] = [];
  @State notes: Note[] = [];
  @State aiKeySet: boolean = false;
  @State type: number = 0;          // 0 = 日复盘，1 = 周复盘
  @State did: string = '';
  @State stuck: string = '';
  @State tomorrow: string = '';
  @State summary: string = '';
  @State saving: boolean = false;
  @State drafting: boolean = false;
  @State msg: string = '';
  @State toTaskBusy: boolean = false;
  onNavigate: (page: string) => void = () => {};
  @State toTaskMsg: string = '';
  @State loadedKey: string = '';
  private unsub: () => void = () => {};

  private syncStore(): void {
    this.reviews = Store.I.reviews;
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.aiKeySet = this.aiKeySet;
    this.recalc();
  }

  /** v4.5：本周汇总的计数预计算进 @State */
  private recalc(): void {
    this.kWeekDone = this.weekDoneTasks().length;
    this.kWeekNotes = this.weekNotes();
    this.kHistory = this.historyOf().length;
  }

  aboutToAppear(): void {
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
    this.syncFromStore();
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  // ── 键 ──
  private todayStr(): string { return D.today(); }

  private weeklyKey(): string { return D.weekStart(); }

  private dateKey(): string { return this.type === 0 ? this.todayStr() : this.weeklyKey(); }

  private typeStr(): 'daily' | 'weekly' { return this.type === 0 ? 'daily' : 'weekly'; }

  private findReview(): Review | null {
    const key: string = this.dateKey();
    const t: string = this.typeStr();
    for (const r of this.reviews) {
      if (r.date === key && r.type === t) { return r; }
    }
    return null;
  }

  /** 切日/周、或者数据重新拉回来后，把表单同步成那篇的内容 */
  private syncFromStore(): void {
    const key: string = `${this.typeStr()}-${this.dateKey()}`;
    if (this.loadedKey === key) { return; }
    this.loadedKey = key;
    const r: Review | null = this.findReview();
    if (r !== null) {
      this.did = r.did;
      this.stuck = r.stuck;
      this.tomorrow = r.tomorrow;
      this.summary = r.summary;
    } else {
      this.did = '';
      this.stuck = '';
      this.tomorrow = '';
      this.summary = '';
    }
    this.msg = '';
  }

  private switchType(t: number): void {
    if (this.type === t) { return; }
    this.type = t;
    this.recalc();
    this.toTaskMsg = '';
    this.syncFromStore();
  }

  private isEmpty(): boolean {
    return this.did.trim().length === 0 && this.stuck.trim().length === 0
      && this.tomorrow.trim().length === 0 && this.summary.trim().length === 0;
  }

  // ── 本周统计 ──
  private weekDoneTasks(): Task[] {
    const ws: string = this.weeklyKey();
    const out: Task[] = [];
    for (const t of this.tasks) {
      if (t.status !== 'done' || t.done_at === null) { continue; }
      if (D.dateOf(t.done_at) >= ws) { out.push(t); }
    }
    return out;
  }

  /**
   * 本周写下的记录数。
   * v4.4：① 用 updated_at（改了也算本周写的，跟网页版一致），不用 created_at；
   * ② 空记录（标题正文都空）不计入 —— 否则点两次起稿词就会虚增。
   */
  private weekNotes(): number {
    const ws: string = this.weeklyKey();
    let n = 0;
    for (const note of this.notes) {
      if (note.title.trim().length === 0 && note.content.trim().length === 0) { continue; }
      if (D.dateOf(note.updated_at) >= ws) { n += 1; }
    }
    return n;
  }

  private historyOf(): Review[] {
    const t: string = this.typeStr();
    const out: Review[] = this.reviews.filter((r: Review) => r.type === t);
    return out.slice(0, 12);   // v4.4：网页版是 12 条
  }

  // v4.3：AI 入口隐藏后 aiReady() 不再被调用（离线版也没有 AI Key 这回事），先留着不删。
  private aiReady(): boolean {
    return this.aiKeySet;
  }

  // ── 动作 ──
  private async save(): Promise<void> {
    if (this.isEmpty()) {
      this.msg = '写一句再保存吧';
      toast(this.getUIContext(), '写一句再保存吧');
      return;
    }
    this.saving = true;
    this.msg = '';
    const body: ReviewSave = {
      date: this.dateKey(),
      type: this.typeStr(),
      did: this.did,
      stuck: this.stuck,
      tomorrow: this.tomorrow,
      summary: this.summary
    } as ReviewSave;
    const ok: boolean = await Store.I.saveReview(body);
    this.saving = false;
    if (ok) {
      this.msg = '已保存';
      this.loadedKey = '';
      this.syncFromStore();
      this.msg = '已保存';
    } else {
      this.msg = Store.I.lastError.length > 0 ? Store.I.lastError : '保存失败，请重试';
    }
  }

  /** 删除复盘：先弹自绘确认框，确认了才真删 */
  private remove(r: Review): void {
    const when: string = r.date.length > 0 ? r.date : '这篇';
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '删除这篇复盘？', `「${when}」的复盘会被移除，删除后无法恢复。`, '删除',
      () => { this.doRemove(r); });
  }

  /** 确认之后才真的删 */
  private async doRemove(r: Review): Promise<void> {
    try {
      await Repo.deleteReview(r.id);
      await Store.I.reloadReviews();
      if (r.date === this.dateKey() && r.type === this.typeStr()) {
        this.did = '';
        this.stuck = '';
        this.tomorrow = '';
        this.summary = '';
      }
      this.msg = '已删除这篇复盘';
      toast(this.getUIContext(), '已删除这篇复盘');
    } catch (e) {
      this.msg = (e as Error).message;
      toast(this.getUIContext(), this.msg);
    }
  }

  private async draft(): Promise<void> {
    this.drafting = true;
    this.msg = '';
    try {
      // v4.0：本地规则起稿 —— 按本地任务/记录数据算，不用联网
      const data: ReviewDraft = LocalAI.review(
        this.dateKey(), this.typeStr(), Store.I.tasks, Store.I.notes, Store.I.reviews);
      if (data.did.length > 0) { this.did = data.did; }
      if (data.stuck.length > 0) { this.stuck = data.stuck; }
      if (data.tomorrow.length > 0) { this.tomorrow = data.tomorrow; }
      this.msg = '已按本地数据起稿，改完记得保存';
      toast(this.getUIContext(), '已按本地数据起稿，改完记得保存');
    } catch (e) {
      this.msg = (e as Error).message;
      toast(this.getUIContext(), this.msg);
    }
    this.drafting = false;
  }

  private async makeTask(): Promise<void> {
    const text: string = this.tomorrow.trim();
    if (text.length === 0) {
      this.toTaskMsg = '先写一件再存';
      return;
    }
    this.toTaskBusy = true;
    this.toTaskMsg = '';
    const due: string = D.key(D.dateAdd(new Date(), 1));
    const body: TaskCreate = {
      title: text.slice(0, 80),
      note: `来自${this.type === 0 ? '日' : '周'}复盘 ${this.todayStr()}`,
      due_date: due,
      area: 'work',
      priority: 'high'
    } as TaskCreate;
    try {
      await Repo.createTask(body);
      this.toTaskMsg = '已存成任务，截止明天';
      this.tomorrow = '';
      await Store.I.reloadTasks();
      toast(this.getUIContext(), '已存成任务，截止明天');
    } catch (e) {
      this.toTaskMsg = (e as Error).message;
    }
    this.toTaskBusy = false;
  }

  // ── 视图 ──
  @Builder qBlock(no: string, label: string, placeholder: string, value: string, minH: number, kind: number) {
    Column({ space: 6 }) {
      Row({ space: 5 }) {
        Text(no).fontSize(10).fontWeight(FontWeight.Bold).fontColor(tkInk(this.dark, 'brandDeep'))
        Text(label).fontSize(11).fontColor(tc(this.dark, '#5E7183', 1))
      }
      .alignItems(VerticalAlign.Center)
      if (kind === 1) {
        TextArea({ placeholder: placeholder, text: value })
          .fontSize(12).constraintSize({ minHeight: minH })
          .placeholderFont({ size: 12 })
          .placeholderColor(tc(this.dark, '#A8B8C6', 1))
          .fontColor(tk(this.dark, 'text'))
          .caretColor(tk(this.dark, 'brand'))
          .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
          .border({ width: 1, color: tk(this.dark, 'line') })
          .padding(10).width('100%')
          .onChange((v: string) => {
            if (no === '01') { this.did = v; }
            else if (no === '02') { this.stuck = v; }
            else { this.tomorrow = v; }
          })
      } else {
        TextArea({ placeholder: placeholder, text: value })
          .fontSize(12).constraintSize({ minHeight: minH })
          .placeholderFont({ size: 12 })
          .placeholderColor(tc(this.dark, '#A8B8C6', 1))
          .fontColor(tk(this.dark, 'text'))
          .caretColor(tk(this.dark, 'brand'))
          .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
          .border({ width: 1, color: tk(this.dark, 'line') })
          .padding(10).width('100%')
          .onChange((v: string) => { this.summary = v; })
      }
    }
    .width('100%')
    .margin({ bottom: 13 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder historyItem(r: Review) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text(`${r.date} · ${r.type === 'weekly' ? '周复盘' : '日复盘'}`)
          .fontSize(9).fontColor(tc(this.dark, '#6A7F92', 1)).layoutWeight(1)
        SymbolGlyph(sym('trash')).fontSize(14).fontColor([tc(this.dark, '#C3D2DE', 1)])
          .padding(3)
          .onClick(() => { this.remove(r); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(r.summary.length > 0 ? r.summary : (r.did.length > 0 ? r.did : '这篇没写内容'))
        .fontSize(10).fontColor(r.summary.length > 0 || r.did.length > 0 ? tc(this.dark, '#78899C', 1) : tc(this.dark, '#B6C8D6', 1))
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: '#F2F7FB' })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder pageTop() {
    TopBar({
      primaryText: this.saving ? '保存中…' : '保存复盘',
      // v4.3：AI 入口先隐藏（用户要求，等做数据线上版再开）。
      // 起稿逻辑还在 db/LocalAI.ets（本地规则、不联网），把下面两行放回来即可：
      //   secondaryText: this.drafting ? '起稿中…' : 'AI 起稿',
      //   onSecondary: () => { this.draft(); },
      secondaryText: '',
      onPrimary: () => { this.save(); },
      onSearch: () => { this.onNavigate('search'); },
      onCalendar: () => { this.onNavigate('calendar'); }
    })
      .width('100%')
  }

  build() {
    Scroll() {
      Column() {
        Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

        this.pageTop()

        // page-head
        Column({ space: 5 }) {
          Text(`REVIEW · ${this.type === 0 ? D.dotDate(new Date()) : this.weeklyKey() + ' 周'}`)
            .fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
          Text(this.type === 0 ? '今天，留下了什么？' : '这一周，走到了哪里？')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
          Text(this.type === 0
            ? '三个问题，30 秒。写给明天的自己看。'
            : `自动汇总：本周完成 ${this.kWeekDone} 件任务，写下 ${this.kWeekNotes} 条记录。`)
            .fontSize(11).fontColor(tk(this.dark, 'textSub'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14, bottom: 12 })

        Row({ space: 6 }) {
          Chip({ text: '日复盘', active: this.type === 0, onTap: () => { this.switchType(0); } })
          Chip({ text: '周复盘', active: this.type === 1, onTap: () => { this.switchType(1); } })
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 复盘表单
        Card({ title: this.type === 0 ? '今日复盘' : '本周复盘', sub: this.type === 0 ? '不用写长，写具体就好。' : '本周完成的情况见下方统计，从这里开始写。', bodyPadTop: 8 }) {
          Column({ space: 0 }) {
            if (this.type === 1) {
              Column({ space: 3 }) {
                Row({ space: 4 }) {
                  Text('本周自动统计：完成').fontSize(11.5).fontColor(tc(this.dark, '#6A7F92', 1))
                  Text(`${this.kWeekDone}`).fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(tkInk(this.dark, 'brandDeep'))
                  Text('件任务，留下').fontSize(11.5).fontColor(tc(this.dark, '#6A7F92', 1))
                  Text(`${this.kWeekNotes}`).fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(tkInk(this.dark, 'brandDeep'))
                  Text('条记录。').fontSize(11.5).fontColor(tc(this.dark, '#6A7F92', 1))
                }
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')
              .padding(10)
              .borderRadius(10)
              .backgroundColor(tc(this.dark, '#F5FAFD', 0))
              .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E9F3FA', 2), 2) })
              .alignItems(HorizontalAlign.Start)
              .margin({ bottom: 12 })
            }

            this.qBlock('01',
              this.type === 0 ? '今天做成了什么？' : '本周做成了什么？',
              this.type === 0 ? '哪怕很小的一件事…' : '把完成的事拢一拢…',
              this.did, 76, 1)

            this.qBlock('02',
              this.type === 0 ? '哪里卡住了？' : '这周卡在哪里？',
              this.type === 0 ? '写下来，明天绕开。' : '下周想绕开什么？',
              this.stuck, 76, 1)

            this.qBlock('03',
              this.type === 0 ? '明天最重要的一件事？' : '下周最重要的一件事？',
              '只写一件。',
              this.tomorrow, 76, 1)

            // 存成任务
            Row({ space: 8 }) {
              Text(this.toTaskBusy ? '存着…' : '存成任务')
                .fontSize(11).fontColor(tc(this.dark, '#5E7183', 1))
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .borderRadius(9)
                .backgroundColor(tk(this.dark, 'card')).border({ width: 1, color: tk(this.dark, 'line') })
                .onClick(() => { this.makeTask(); })
              Text('截止日设为明天').fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1))
              if (this.toTaskMsg.length > 0) {
                Text(this.toTaskMsg).fontSize(9.5).fontColor(tkInk(this.dark, 'brandDeep'))
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: -6, bottom: 14 })

            // 一句话总结
            Column({ space: 6 }) {
              Text('一句话总结（可选）').fontSize(11).fontColor(tc(this.dark, '#5E7183', 1))
              TextArea({ placeholder: '给这段一个句号。', text: this.summary })
                .fontSize(12).constraintSize({ minHeight: 54 })
                .placeholderFont({ size: 12 })
                .placeholderColor(tc(this.dark, '#A8B8C6', 1))
                .fontColor(tk(this.dark, 'text'))
                .caretColor(tk(this.dark, 'brand'))
                .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
                .border({ width: 1, color: tk(this.dark, 'line') })
                .padding(10).width('100%')
                .onChange((v: string) => { this.summary = v; })
            }
            .width('100%')
            .margin({ bottom: 14 })
            .alignItems(HorizontalAlign.Start)

            // 按钮行
            Row({ space: 8 }) {
              Text(this.saving ? '保存中…' : '保存复盘')
                .fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(onFill(this.dark))
                .padding({ left: 15, right: 15, top: 9, bottom: 9 })
                .borderRadius(S.radiusBtn)
                .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
                .opacity(this.saving ? 0.6 : 1)
                .onClick(() => { this.save(); })
              // v4.3：AI 入口先隐藏（等做数据线上版再开）。代码保留，取消注释即可恢复：
              // Row({ space: 4 }) {
              //   SymbolGlyph(sym('wand')).fontSize(11).fontColor([tc(this.dark, '#5E7183', 1)])
              //   Text(this.drafting ? '起稿中…' : '让 AI 起稿').fontSize(11).fontColor(tc(this.dark, '#5E7183', 1))
              // }
              // .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              // .borderRadius(S.radiusBtn)
              // .backgroundColor(tk(this.dark, 'card')).border({ width: 1, color: tk(this.dark, 'line') })
              // .alignItems(VerticalAlign.Center)
              // .opacity(this.drafting ? 0.6 : 1)
              // .onClick(() => { this.draft(); })
              if (this.msg.length > 0) {
                Text(this.msg).fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1)).layoutWeight(1)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // v4.3：离线版没有 AI Key 了，这行提示一起去掉。
            // if (!this.aiReady()) {
            //   Text('（离线本地起稿，不用联网）').fontSize(9).fontColor(tc(this.dark, '#B7C7D4', 1))
            //     .width('100%').margin({ top: 6 })
            // }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // 历史
        Column() {
          Card({ title: `最近${this.type === 0 ? '日' : '周'}复盘`, sub: '回头看，才知道自己走了多远。', bodyPadTop: 6 }) {
            Column({ space: 0 }) {
              if (this.kHistory === 0) {
                Column({ space: 5 }) {
                  Text(`还没有${this.type === 0 ? '日' : '周'}复盘`)
                    .fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(tc(this.dark, '#5E7183', 1))
                  Text('从上面这几行开始，30 秒就够。').fontSize(10.5).fontColor(tc(this.dark, '#A8B8C6', 1))
                }
                .width('100%')
                .padding({ top: 24, bottom: 24 })
                .alignItems(HorizontalAlign.Center)
              } else {
                ForEach(this.historyOf(), (r: Review) => {
                  this.historyItem(r)
                }, (r: Review) => `rv-${r.id}-${r.updated_at}-${this.tick}`)
              }

              // 底部统计
              Row({ space: 10 }) {
                Column({ space: 1 }) {
                  Text('本周完成任务').fontSize(10).fontColor(tc(this.dark, '#8FA2B3', 1))
                  Text(`${this.kWeekDone}`).fontSize(16).fontWeight(FontWeight.Bold).fontColor(tc(this.dark, '#2B4055', 1))
                }
                .layoutWeight(1)
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(11)
                .backgroundColor(tc(this.dark, '#F6FAFE', 0))
                .alignItems(HorizontalAlign.Start)

                Column({ space: 1 }) {
                  Text('本周写下的记录').fontSize(10).fontColor(tc(this.dark, '#8FA2B3', 1))
                  Text(`${this.kWeekNotes}`).fontSize(16).fontWeight(FontWeight.Bold).fontColor(tc(this.dark, '#2B4055', 1))
                }
                .layoutWeight(1)
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(11)
                .backgroundColor(tc(this.dark, '#F6FAFE', 0))
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .margin({ top: 12 })
              .padding({ top: 12 })
              .border({ width: { top: 1 }, color: '#F2F7FB' })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
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

