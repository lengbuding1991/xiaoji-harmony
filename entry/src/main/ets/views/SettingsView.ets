// 设置
// v4.0：纯离线版。没有服务器、没有账号、没有密码 ——
// 所有数据都存在这台手机自己的数据库里（db/Db.ets + db/Repo.ets）。
// 这一页负责三件事：
//   1) 让你看清「我的数据在本机」：各类内容多少条、存在哪
//   2) 备份与恢复：导出 JSON 到剪贴板 / 从剪贴板导入（换机、留底）
//   3) 清空全部数据（自绘确认弹窗）
// v4.20：零权限 —— 系统通知 / 代理提醒整条线已移除，本 App 不申请任何系统权限。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Store } from '../store/Store';
import { Repo } from '../db/Repo';
import { C, onFill, S, tc, tk } from '../utils/Theme';
import { D } from '../utils/DateUtil';
import { Card } from '../components/Card';
import { sym } from '../components/Icon';
import { toast } from '../utils/Toast';
import { Confirm } from '../utils/Confirm';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { SettingsResp, SettingsPatch, Task, Note, Review, EventItem, Project, HabitView } from '../api/Types';
import { bundleManager } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { TopBar } from '../components/TopBar';
import { onEdgeScrolled, onEdgeWillScroll } from '../utils/EdgeHint';

@Component
export struct SettingsView {
  // v4.8：深色模式（变了要重画本组件）
  @StorageLink('wb_dark') dark: boolean = false;
  @State tick: number = 0;
  @State settings: SettingsResp = { user_name: '', ai_base_url: '', ai_model: '', ai_key_set: false };
  @State tasks: Task[] = [];
  @State notes: Note[] = [];
  @State reviews: Review[] = [];
  @State events: EventItem[] = [];
  @State projects: Project[] = [];
  // v4.4：习惯数原来直接读 Store.I.habits.length —— 那是普通字段不是 @State，
  // 导入/清空之后数字不会自己变，所以改成同步一份到 @State。
  @State habits: HabitView[] = [];
  @State userName: string = '';
  // 版本号从系统读，改了 app.json5 不用再改这里
  @State appVersion: string = 'v1.0.0';
  @State busy: boolean = false;
  @State backupText: string = '';
  private unsub: () => void = () => {};

  private readVersion(): void {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(0);
      this.appVersion = `v${info.versionName} (${info.versionCode})`;
    } catch (e) {
      this.appVersion = 'v1.0.0';
    }
  }

  private syncStore(): void {
    this.settings = Store.I.settings;
    this.tasks = Store.I.tasks;
    this.notes = Store.I.notes;
    this.reviews = Store.I.reviews;
    this.events = Store.I.events;
    this.projects = Store.I.projects;
    this.habits = Store.I.habits;
  }
  onNavigate: (page: string) => void = () => {};

  aboutToAppear(): void {
    this.readVersion();
    this.syncStore();
    this.unsub = Store.I.subscribe(() => { this.tick += 1; this.syncStore(); });
    this.userName = this.settings.user_name;
  }

  aboutToDisappear(): void {
    this.unsub();
  }

  // ───────────────────────── 本地数据 ─────────────────────────

  /** 把整个本地库导出成一段 JSON 文本（复制到剪贴板，换机时用） */
  private async exportBackup(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const text: string = await Repo.exportJson();
      const pb = pasteboard.getSystemPasteboard();
      await pb.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      const kb: number = Math.round(text.length / 1024);
      toast(this.getUIContext(), `已复制 ${kb}KB 备份到剪贴板`);
    } catch (e) {
      toast(this.getUIContext(), '导出失败：' + (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  /**
   * 从备份文本恢复（覆盖式：先清空再写入）。
   * 备份内容由用户长按粘贴进下面的输入框 —— 不用读剪贴板的权限，
   * 也不会碰到系统弹权限框。
   */
  private async restoreFromText(): Promise<void> {
    hilog.debug(0x0000, 'workbench', 'restoreFromText enter busy=%{public}d len=%{public}d', this.busy ? 1 : 0, this.backupText.length);
    if (this.busy) { return; }
    const text: string = this.backupText.trim();
    if (text.length === 0) {
      toast(this.getUIContext(), '先把备份内容粘贴进来');
      return;
    }
    this.busy = true;
    try {
      const r = await Repo.importJson(text);
      await Store.I.loadAll();
      this.backupText = '';
      toast(this.getUIContext(), `已恢复 ${r.count} 条内容`);
    } catch (e) {
      // v4.4：失败文案必须写明「原数据没有动」——之前是「先清库再报错」，会吓人
      toast(this.getUIContext(), (e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  /** 恢复是覆盖式的：先弹确认，让人知道「现在这份会被换掉」 */
  private askRestore(): void {
    if (this.busy) { return; }
    if (this.backupText.trim().length === 0) {
      toast(this.getUIContext(), '先把备份内容粘贴进来');
      return;
    }
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '用备份覆盖现在的数据？',
      '这台手机上的任务、日程、记录、项目、复盘和习惯都会被备份里的内容替换掉，替换后找不回来。建议先「复制备份」留一份现在的。',
      '覆盖恢复',
      () => { this.restoreFromText(); });
  }

  /** 清空全部数据（危险操作，必须走自绘确认弹窗） */
  private askClear(): void {
    Confirm.open(this.getUIContext(), () => { this.confirmBuilder(); },
      '清空全部数据？',
      '这台手机上的任务、日程、记录、项目、复盘和习惯都会被删除，删掉找不回来。建议先复制一份备份。',
      '全部清空',
      () => { this.doClear(); });
  }

  private async doClear(): Promise<void> {
    try {
      await Repo.clearAll();
      await Store.I.loadAll();
      toast(this.getUIContext(), '已清空');
    } catch (e) {
      toast(this.getUIContext(), '清空失败：' + (e as Error).message);
    }
  }

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

  // v4.20：零权限 —— 系统通知 / 代理提醒整条线已移除，下面不再有提醒相关方法。

  private async saveName(): Promise<void> {
    const body: SettingsPatch = { user_name: this.userName } as SettingsPatch;
    // v4.4：用 saveSettings 的返回值判成败。原来读 Store.I.lastError ——
    // 那个值可能是上一次搜索失败留下的，保存成功也会弹一个旧错误。
    const ok: boolean = await Store.I.saveSettings(body);
    toast(this.getUIContext(), ok ? '存好了' : '没存上，再试一次');
  }

  /** v4.8：切换深色模式（存本地 + 立刻生效） */
  private toggleDark(on: boolean): void {
    AppStorage.set<boolean>('wb_dark', on);
    this.dark = on;
    Store.I.setDark(on).then((ok: boolean) => {
      if (!ok) {
        toast(this.getUIContext(), '没存上，重启后再试一次');
      }
    });
  }

  // ── 小块组件 ──
  @Builder fieldLabel(text: string) {
    Text(text).fontSize(9.5).fontColor(tc(this.dark, '#8FA2B3', 1)).width('100%')
  }

  @Builder primaryBtn(text: string, cb: () => void) {
    Text(text)
      .fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(onFill(this.dark))
      .textAlign(TextAlign.Center)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(S.radiusBtn)
      .linearGradient({ angle: 140, colors: [['#1C7C74', 0], ['#1B7799', 1]] })
      .layoutWeight(1)
      .onClick(cb)
  }

  @Builder ghostBtn(text: string, cb: () => void) {
    Text(text)
      .fontSize(11.5).fontColor(tc(this.dark, '#5E7183', 1))
      .textAlign(TextAlign.Center)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(S.radiusBtn)
      .backgroundColor(tc(this.dark, '#FFFFFF', 0))
      .border({ width: 1, color: tk(this.dark, 'line') })
      .layoutWeight(1)
      .onClick(cb)
  }

  @Builder statBox(label: string, value: string, sub: string) {
    Column({ space: 2 }) {
      Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor(tc(this.dark, '#2E4A5E', 1)).letterSpacing(-0.5)
      Text(label).fontSize(9.5).fontColor(tc(this.dark, '#9FB2C2', 1))
      Text(sub).fontSize(8.5).fontColor(tc(this.dark, '#B6C7D4', 1))
    }
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .borderRadius(13)
    .backgroundColor(tc(this.dark, '#F7FBFE', 0))
    .border({ width: 1, color: tc(this.dark, tc(this.dark, '#E9F3FA', 2), 2) })
    .alignItems(HorizontalAlign.Start)
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
    Scroll() {
      Column() {
        Text(`${this.tick}`).fontSize(1).width(1).height(1).opacity(0)

        this.pageTop()

        // page-head
        Column({ space: 5 }) {
          Text('SETTINGS · 偏好设置').fontSize(9).fontColor(tc(this.dark, '#9DB0C1', 1)).letterSpacing(1.6)
          Text('这里是你的工作台。')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(tk(this.dark, 'text')).letterSpacing(-0.5)
          Text('所有数据都存在这台手机上，不联网、不上传。').fontSize(11).fontColor(tk(this.dark, 'textSub'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14, bottom: 14 })

        // 概览
        Row({ space: 9 }) {
          this.statBox('任务', `${this.tasks.length}`, '件')
          this.statBox('记录', `${this.notes.length}`, '条')
          this.statBox('复盘', `${this.reviews.length}`, '篇')
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 本地数据
        Card({ title: '本地数据', sub: '都在这台手机里', bodyPadTop: 8 }) {
          Column({ space: 8 }) {
            Row() {
              Row() {
                SymbolGlyph(sym('checkCircle')).fontSize(13).fontColor([tc(this.dark, '#1F9E9A', 1)])
              }
              .width(30).height(30).borderRadius(10)
              .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
              .backgroundColor(tc(this.dark, '#E1F7F5', 0))
              Column({ space: 2 }) {
                Text('离线模式已开启').fontSize(11).fontColor(tk(this.dark, 'text'))
                Text('不需要登录，不需要联网，打开就能用')
                  .fontSize(9).fontColor(tc(this.dark, '#8FA2B3', 1))
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Divider().color(tk(this.dark, 'line')).strokeWidth(1)

            // 各类内容条数
            Row() {
              this.miniStat('任务', this.tasks.length)
              this.miniStat('日程', this.events.length)
              this.miniStat('记录', this.notes.length)
            }
            .width('100%')
            Row() {
              this.miniStat('项目', this.projects.length)
              this.miniStat('复盘', this.reviews.length)
              this.miniStat('习惯', this.habits.length)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // 备份与恢复
        Column() {
          Card({ title: '备份与恢复', sub: '换手机也不怕', bodyPadTop: 8 }) {
            Column({ space: 8 }) {
              Text('「复制备份」把全部内容打包成一段文字放进剪贴板，你可以粘贴到备忘录、聊天窗口或存成文件。')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(17).width('100%')
              Row({ space: 8 }) {
                this.primaryBtn(this.busy ? '处理中…' : '复制备份', () => { this.exportBackup(); })
                this.ghostBtn('清空输入框', () => { this.backupText = ''; })
              }
              .width('100%')
              Text('恢复：把备份内容长按粘贴到下面这个框里，再点「恢复」。恢复会覆盖当前数据（点「恢复」后会再问一次），建议先复制一份现在的。备份格式不对时不会动你现在的数据。')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(17).width('100%')
              TextArea({ placeholder: '把备份内容粘贴到这里', text: this.backupText })
                .fontSize(11).width('100%')
                .height(84)
                .placeholderFont({ size: 11 })
                .placeholderColor(tc(this.dark, '#A8B8C6', 1))
                .fontColor(tk(this.dark, 'text'))
                .caretColor(tk(this.dark, 'brand'))
                .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
                .border({ width: 1, color: tk(this.dark, 'line') })
                .padding({ left: 11, right: 11, top: 8, bottom: 8 })
                .onChange((v: string) => { this.backupText = v; })
              Row({ space: 8 }) {
                this.primaryBtn(this.busy ? '处理中…' : '恢复', () => { hilog.debug(0x0000, 'workbench', 'restore button tapped'); this.askRestore(); })
              }
              .width('100%')
              Text('数据存在 App 自己的沙盒数据库里，卸载 App 会一起删除 —— 想留底就复制一份备份。')
                .fontSize(9).fontColor(tc(this.dark, '#C89A5B', 1)).lineHeight(16).width('100%')
                .padding({ top: 6, bottom: 6, left: 10, right: 10 })
                .backgroundColor(tc(this.dark, '#FFF8EC', 0)).borderRadius(9)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 称呼
        Column() {
          Card({ title: '称呼', sub: '会显示在首页问候语右上角', bodyPadTop: 8 }) {
            Column({ space: 8 }) {
              this.fieldLabel('怎么称呼你（保存后，首页问候语右上角会出现这个小人图标和名字）')
              TextInput({ placeholder: '你的名字', text: this.userName })
                .fontSize(12).height(38).width('100%')
                .placeholderFont({ size: 12 })
                .placeholderColor(tc(this.dark, '#A8B8C6', 1))
                .fontColor(tk(this.dark, 'text'))
                .caretColor(tk(this.dark, 'brand'))
                .backgroundColor(tc(this.dark, '#F8FBFE', 0)).borderRadius(11)
                .border({ width: 1, color: tk(this.dark, 'line') })
                .padding({ left: 11, right: 11 })
                .onChange((v: string) => { this.userName = v; })
              Row() {
                this.primaryBtn('保存名字', () => { this.saveName(); })
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 提醒清单说明（v4.20：零权限 —— 只用 App 内的铃铛清单，不发系统通知）
        Column() {
          Card({ title: '提醒清单', sub: '在 App 顶部的铃铛里看', bodyPadTop: 8 }) {
            Column({ space: 8 }) {
              Text('App 顶部铃铛里会列出「已经逾期」「今天到期」「12 小时内要做」的事，随时点开就能看。')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(17).width('100%')
              Text('这一版不申请任何系统权限，也不会发系统通知 —— 提醒只在 App 打开时自己出现在铃铛里。')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(17).width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 危险操作
        Column() {
          Card({ title: '清空数据', sub: '不可撤销', bodyPadTop: 8 }) {
            Column({ space: 8 }) {
              Text('把手机上的所有内容一次性删掉，回到刚安装的状态。删掉就找不回来了，动手前请先复制备份。')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(17).width('100%')
              Row() {
                Text('清空全部数据')
                  .fontSize(11.5).fontColor(tc(this.dark, '#D4705F', 1)).textAlign(TextAlign.Center)
                  .width('100%').padding({ top: 9, bottom: 9 })
                  .borderRadius(S.radiusBtn)
                  .backgroundColor(tc(this.dark, '#FDF2EF', 0))
                  .border({ width: 1, color: tc(this.dark, tc(this.dark, '#F8DCD7', 2), 2) })
                  .onClick(() => { this.askClear(); })
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // v4.8 外观
        Column() {
          Card({ title: '外观', sub: '深色模式夜里看不刺眼', bodyPadTop: 8 }) {
            Column({ space: 8 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('深色模式').fontSize(11.5).fontColor(tk(this.dark, 'text'))
                  Text('切换后整个 App 的底色、文字、卡片都会跟着变')
                    .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.dark })
                  .selectedColor(tk(this.dark, 'brand'))
                  .switchPointColor('#FFFFFF')
                  .onChange((on: boolean) => { this.toggleDark(on); })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 隐私与协议
        Column() {
          Card({ title: '隐私与协议', sub: '不联网 · 不收集个人信息', bodyPadTop: 8 }) {
            Column({ space: 8 }) {
              Text('本 App 不申请网络权限、不收集任何个人信息，所有内容只存在这台手机上。完整的《用户协议》和《隐私政策》都在 App 里，随时可以看。')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(17).width('100%')
              Row() {
                this.primaryBtn('查看用户协议与隐私政策', () => { this.onNavigate('policy'); })
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        // 关于
        Column() {
          Card({ title: '关于', bodyPadTop: 8 }) {
            Column({ space: 5 }) {
              Text('小记 · 鸿蒙端').fontSize(11.5).fontColor(tk(this.dark, 'text')).width('100%')
              Text('纯离线版：数据只存在这台手机上，不连服务器，也不需要账号。')
                .fontSize(9.5).fontColor(tc(this.dark, '#A8B8C6', 1)).lineHeight(17).width('100%')
              Text(`本机数据库 · ${this.appVersion} · ${D.dotDate(new Date())}`)
                .fontSize(9).fontColor(tc(this.dark, '#B7C7D4', 1)).width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .margin({ top: 12 })

        Text(`离线版 · 数据存在本机 · ${this.appVersion} · ${D.dotDate(new Date())}`)
          .fontSize(9).fontColor(tc(this.dark, '#C6D4E0', 1)).textAlign(TextAlign.Center)
          .width('100%').margin({ top: 12, bottom: S.pageBottom })
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

  @Builder
  miniStat(label: string, n: number) {
    Column({ space: 1 }) {
      Text(`${n}`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(tc(this.dark, '#2E4A5E', 1))
      Text(label).fontSize(9).fontColor(tc(this.dark, '#9FB2C2', 1))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }
}
