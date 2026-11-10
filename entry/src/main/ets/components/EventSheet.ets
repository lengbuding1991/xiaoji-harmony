/**
 * EventSheet —— 日程添加/编辑抽屉，对齐个人工作台 components/CalendarApp.tsx 的日程弹窗。
 *
 * 工作台字段（严格此序）：
 *   标题 → 全天事件 checkbox → [开始 | 结束] → 地点 → 备注 → 重复
 * 标题：编辑时「编辑日程」/ 新建时「新日程」
 * 副标题：编辑「改完直接保存。」/ 新建「先占住时间，比事后补记有用。」
 * 动作：删除(编辑时) / 取消 / 保存
 *
 * v4.20：零权限 —— 「提醒」选项整块删掉（本 App 不发系统通知、不申请任何权限）。
 *   remind_min 字段在 db 里保留，老日程的提前量继续生效。
 */
import { C, onFill, tc, tk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { sym } from './Icon';
import { SheetHead, FormBox, PickerBox, DateBox, FormErr, SheetActs } from './FormKit';
import { EventCreate, EventUpdate, EventItem, RepeatRule } from '../api/Types';
import { Store } from '../store/Store';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from './ConfirmDialog';
import { R } from '../utils/Responsive';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

const RULE_KEYS: string[] = ['none', 'daily', 'weekdays', 'weekly', 'monthly'];
const RULE_LABELS: string[] = ['不重复', '每天', '每个工作日', '每周', '每月'];

@Component
export struct EventSheet {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @Prop @Watch('reload') editingId: number = -1;
  /** 新建时的默认日期 yyyy-MM-dd */
  @Prop @Watch('reload') defaultDate: string = '';
  /** 新建时的默认开始时间 HH:mm（点空闲块时传入） */
  @Prop @Watch('reload') defaultStart: string = '';
  /** 新建时的默认结束时间 HH:mm */
  @Prop @Watch('reload') defaultEnd: string = '';

  onSaved: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  @State title: string = '';
  @State allDay: boolean = false;
  @State startAt: string = '';
  @State endAt: string = '';
  @State place: string = '';
  @State note: string = '';
  @State rule: string = 'none';
  @State busy: boolean = false;
  @State err: string = '';
  /** v4.12：关联任务（-1 = 不关联） */
  @State linkTaskId: number = -1;
  @State linkTaskLabels: string[] = [];
  @State linkTaskIds: number[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.title = '';
    this.allDay = false;
    this.startAt = '';
    this.endAt = '';
    this.place = '';
    this.note = '';
    this.rule = 'none';
    this.busy = false;
    this.err = '';
    this.linkTaskId = -1;
    this.buildTaskChoices();
    if (this.editingId > 0) {
      for (const e of Store.I.events) {
        if (e.id === this.editingId) {
          this.title = e.title;
          this.allDay = e.all_day === 1;
          this.startAt = e.start_at;
          this.endAt = e.end_at !== null ? e.end_at : '';
          this.place = e.location !== null ? e.location : '';
          this.note = e.note !== null ? e.note : '';
          this.rule = e.repeat_rule;
          break;
        }
      }
    } else {
      const d: string = this.defaultDate.length > 0 ? this.defaultDate : D.today();
      const h: number = new Date().getHours();
      const s: string = this.defaultStart.length > 0 ? this.defaultStart : `${h < 10 ? '0' : ''}${h}:00`;
      const e2: number = h + 1 >= 24 ? 23 : h + 1;
      const en: string = this.defaultEnd.length > 0 ? this.defaultEnd : `${e2 < 10 ? '0' : ''}${e2}:00`;
      this.startAt = `${d}T${s}`;
      this.endAt = `${d}T${en}`;
    }
  }

  /** v4.12：可选的任务（还没做完的，最多 20 条） */
  private buildTaskChoices(): void {
    const labels: string[] = ['不关联任务'];
    const ids: number[] = [-1];
    for (const t of Store.I.tasks) {
      if (t.status === 'done') { continue; }
      if (ids.length > 20) { break; }
      labels.push(t.title);
      ids.push(t.id);
    }
    this.linkTaskLabels = labels;
    this.linkTaskIds = ids;
  }

  /** 编辑态：回显已关联的任务 */
  private async loadEventTaskLink(): Promise<void> {
    try {
      for (const l of Store.I.taskEventLinks) {
        if (l.event_id === this.editingId) { this.linkTaskId = l.task_id; break; }
      }
    } catch (e) {
      this.linkTaskId = -1;
    }
  }

  private linkTaskText(): string {
    for (let i = 0; i < this.linkTaskIds.length; i++) {
      if (this.linkTaskIds[i] === this.linkTaskId) { return this.linkTaskLabels[i]; }
    }
    return '不关联任务';
  }

  private ruleIndex(): number {
    for (let i = 0; i < RULE_KEYS.length; i++) {
      if (RULE_KEYS[i] === this.rule) { return i; }
    }
    return 0;
  }

  private ruleVal(): RepeatRule {
    const i: number = this.ruleIndex();
    if (i === 1) { return 'daily'; }
    if (i === 2) { return 'weekdays'; }
    if (i === 3) { return 'weekly'; }
    if (i === 4) { return 'monthly'; }
    return 'none';
  }

  private startText(): string {
    return this.startAt.length >= 16 ? this.startAt.replace('T', ' ').slice(0, 16) : '选择日期时间';
  }

  private endText(): string {
    return this.endAt.length >= 16 ? this.endAt.replace('T', ' ').slice(0, 16) : '选择日期时间';
  }

  private pickDateTime(current: string, onPick: (v: string) => void): void {
    let sel: Date = new Date();
    let hh: number = 9;
    let mm: number = 0;
    if (current.length >= 16) {
      sel = D.parse(current);
      hh = sel.getHours();
      mm = sel.getMinutes();
    }
    const ui = this.getUIContext();
    ui.showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2035, 11, 31),
      selected: sel,
      onDateAccept: (d: Date) => {
        const base: Date = new Date(d.getFullYear(), d.getMonth(), d.getDate(), hh, mm, 0, 0);
        ui.showTimePickerDialog({
          selected: base,
          useMilitaryTime: true,
          onAccept: (r: TimePickerResult) => {
            const h: string = r.hour < 10 ? `0${r.hour}` : `${r.hour}`;
            const m: string = r.minute < 10 ? `0${r.minute}` : `${r.minute}`;
            onPick(`${D.key(d)}T${h}:${m}`);
          }
        });
      }
    });
  }

  private bodyFields(): EventCreate {
    const body: EventCreate = {
      title: this.title.trim(),
      start_at: this.startAt,
      end_at: this.endAt.length > 0 ? this.endAt : null,
      all_day: this.allDay ? 1 : 0,
      location: this.place,
      note: this.note,
      repeat_rule: this.ruleVal()
    };
    return body;
  }

  /** 改档用：字段可以缺省（PATCH 语义），类型和建档的 EventCreate 分开，避免结构化类型混用 */
  private bodyPatch(): EventUpdate {
    const body: EventUpdate = {
      title: this.title.trim(),
      start_at: this.startAt,
      end_at: this.endAt.length > 0 ? this.endAt : null,
      all_day: this.allDay ? 1 : 0,
      location: this.place,
      note: this.note,
      repeat_rule: this.ruleVal()
    };
    return body;
  }

  private async save(): Promise<void> {
    const title: string = this.title.trim();
    if (title.length === 0) {
      this.err = '日程名不能为空';
      return;
    }
    if (this.startAt.length < 16) {
      this.err = '先选个开始时间';
      return;
    }
    // v4.4：结束时间早于开始时间要拦住（以前能存进去，日历上就成了负数时长）
    if (this.endAt.length >= 16 && this.endAt < this.startAt) {
      this.err = '结束时间要晚于开始时间';
      return;
    }
    this.busy = true;
    this.err = '';
    let ok: boolean = false;
    if (this.editingId > 0) {
      ok = await Store.I.updateEvent(this.editingId, this.bodyPatch());
    } else {
      const body: EventCreate = this.bodyFields() as EventCreate;
      ok = await Store.I.addEvent(body);
    }
    this.busy = false;
    if (ok) {
      // v4.12：把选好的任务关联上
      const eid: number = this.editingId > 0 ? this.editingId : Store.I.lastEventId;
      if (this.linkTaskId > 0 && eid > 0) {
        await Store.I.linkTaskEvent(this.linkTaskId, eid);
      }
      this.onSaved();
    } else {
      this.err = Store.I.lastError.length > 0 ? Store.I.lastError : '保存失败，再试一次';
    }
  }

  private remove(): void {
    const nm: string = this.title.length > 0 ? this.title : '这条日程';
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '删除这条日程？', `「${nm}」会被移除，删除后无法恢复。`, '删除',
      () => { this.doRemove(); });
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

  private async doRemove(): Promise<void> {
    this.busy = true;
    const ok: boolean = await Store.I.deleteEvent(this.editingId);
    this.busy = false;
    if (ok) {
      this.onCancel();
    } else {
      this.err = Store.I.lastError.length > 0 ? Store.I.lastError : '删除失败，再试一次';
    }
  }

  build() {
    Column() {
      Column() {
        SheetHead({
          title: this.editingId > 0 ? '编辑日程' : '新日程',
          sub: this.editingId > 0 ? '改完直接保存。' : '先占住时间，比事后补记有用。',
          showClose: true,
          onClose: () => { this.onCancel(); }
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18 })

      Scroll() {
        Column({ space: 11 }) {
          FormBox({ label: '标题' }) {
            TextInput({ placeholder: '比如：客户周会', text: this.title })
              .onChange((v: string) => { this.title = v; })
              .fontSize(12).height(36)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
              .border({ width: 1, color: tk(this.dark, 'line') })
              .padding({ left: 11, right: 11 })
          }

          // 全天事件
          Row({ space: 7 }) {
            Row() {
              if (this.allDay) {
                // v4.23：fs14 的勾盒子 14x14vp，方框放大到 18vp 才装得下
                SymbolGlyph(sym('check')).fontSize(14).fontColor([onFill(this.dark)])
              }
            }
            .width(18).height(18).borderRadius(5)
            .backgroundColor(this.allDay ? tk(this.dark, 'brand') : tk(this.dark, 'card'))
            .border({ width: 1, color: this.allDay ? tk(this.dark, 'brand') : tk(this.dark, 'line') })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.allDay = !this.allDay; })

            Text('全天事件').fontSize(11).fontColor(tc(this.dark, '#5E7183', 1))
            Blank()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Column({ space: 11 }) {
            FormBox({ label: '开始' }) {
              DateBox({
                text: this.startText(),
                muted: this.startAt.length === 0,
                icon: 'clock',
                onTap: () => { this.pickDateTime(this.startAt, (v: string) => { this.startAt = v; }); }
              })
            }
            FormBox({ label: '结束' }) {
              DateBox({
                text: this.endText(),
                muted: this.endAt.length === 0,
                icon: 'clock',
                onTap: () => { this.pickDateTime(this.endAt, (v: string) => { this.endAt = v; }); }
              })
            }
          }
          .width('100%')

          FormBox({ label: '地点' }) {
            TextInput({ placeholder: '可选', text: this.place })
              .onChange((v: string) => { this.place = v; })
              .fontSize(12).height(36)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
              .border({ width: 1, color: tk(this.dark, 'line') })
              .padding({ left: 11, right: 11 })
          }

          FormBox({ label: '备注' }) {
            TextInput({ placeholder: '可选', text: this.note })
              .onChange((v: string) => { this.note = v; })
              .fontSize(12).height(36)
              .placeholderFont({ size: 12 })
              .placeholderColor(tc(this.dark, '#A8B8C6', 1))
              .fontColor(tk(this.dark, 'text'))
              .caretColor(tk(this.dark, 'brand'))
              .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
              .border({ width: 1, color: tk(this.dark, 'line') })
              .padding({ left: 11, right: 11 })
          }

          Column({ space: 11 }) {
            FormBox({ label: '重复', icon: 'undo' }) {
              PickerBox({
                text: RULE_LABELS[this.ruleIndex()],
                options: RULE_LABELS,
                onPick: (i: number) => { this.rule = RULE_KEYS[i]; }
              })
            }
            FormBox({ label: '关联任务', icon: 'tasks' }) {
              PickerBox({
                text: this.linkTaskText(),
                options: this.linkTaskLabels,
                onPick: (i: number) => { this.linkTaskId = i >= 0 && i < this.linkTaskIds.length ? this.linkTaskIds[i] : -1; }
              })
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 11, bottom: 18 })
        .alignItems(HorizontalAlign.Start)
      }
      .onScrollEdge(onEdgeScrolled)
      .onWillScroll(onEdgeWillScroll)
      .edgeEffect(EdgeEffect.Spring)
      .constraintSize({ maxHeight: R.sheetBodyH() })
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)

      if (this.err.length > 0) {
        Column() {
          FormErr({ msg: this.err })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 8 })
      }

      SheetActs({
        primaryText: '保存',
        secondaryText: '取消',
        dangerText: this.editingId > 0 ? '删除' : '',
        busy: this.busy,
        onPrimary: () => { this.save(); },
        onSecondary: () => { this.onCancel(); },
        onDanger: () => { this.remove(); }
      })
    }
    .width('100%')
    .backgroundColor(tk(this.dark, 'card'))
    .borderRadius(22)
  }
}
