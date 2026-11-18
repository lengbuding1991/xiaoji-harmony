// entry/src/main/ets/utils/Confirm.ets
// v2.9：删除确认统一入口（自绘弹窗，不用系统 AlertDialog）。
//
// 为什么绕这一圈：删除按钮有两种位置——页面里（随手记）和 bindSheet 弹层里（任务/日程）。
// 页面里自绘遮罩没问题，但弹层是独立层，页面级的遮罩盖不住它；
// 所以统一走「系统级自定义弹窗层」UIContext.getPromptAction().openCustomDialog，
// 它和系统 AlertDialog 同层级，能压在 sheet 上面。
// 卡片本体仍是自绘的（components/ConfirmDialog.ets），样式照「个人工作台」的 .cf。
import { UIContext, promptAction } from '@kit.ArkUI';
import { toast } from './Toast';

export class ConfirmOpt {
  title: string = '';
  desc: string = '';
  confirmText: string = '删除';
  onOk: () => void = () => {};
}

export class Confirm {
  /** 弹窗内容参数（打开时写好，卡片直接读） */
  static opt: ConfirmOpt = new ConfirmOpt();
  /** openCustomDialog 返回的弹窗 id；-1 = 当前没有弹窗 */
  static id: number = -1;
  /** 弹窗还没拿到 id 就被点掉了：记下来，等拿到 id 立刻关掉 */
  static pending: boolean = false;
  /** 正在打开中（openCustomDialog 的 Promise 还没回来）—— 这段时间也算「已经有弹窗了」 */
  private static opening: boolean = false;
  /** 打开次数（每次 open 加一）：用来识别「过期的那个弹窗的 onDidDisappear」 */
  private static gen: number = 0;
  /**
   * 这一次弹窗的动作**快照**。
   * v5.14：原来 Confirm.confirm() 读的是全局的 Confirm.opt.onOk ——
   *   如果先后 open 了两个弹窗，后一个把 opt 覆盖了，
   *   **先开的那个点「确认」会执行后一个动作**（可能删错东西）。
   *   现在打开时就把动作拍下来，确认时用自己那一份。
   */
  private static onOkSnapshot: () => void = () => {};

  /**
   * 打开确认弹窗。
   * @param ui 发起页面的 UIContext（用 this.getUIContext() 拿）
   * @param builder 自绘卡片，调用方写成 () => { this.confirmBuilder(); }
   * @param title 标题
   * @param desc 说明
   * @param confirmText 确认按钮文字
   * @param onOk 点「确认」后要做的事（弹窗已关闭）
   */
  static open(ui: UIContext, builder: CustomBuilder, title: string, desc: string,
    confirmText: string, onOk: () => void): void {
    // v5.14：**查重**。
    //   已经有一个确认弹窗（或者正在打开）时，不再开第二个。
    //   原来连开两个会出两个弹窗，而 opt 是全局一份 ⇒
    //   先开的那个点「确认」时执行的是后一个动作（可能删错东西），而且关不干净。
    if (Confirm.id >= 0 || Confirm.opening) {
      toast(ui, '先处理上面那个弹窗');
      return;
    }
    Confirm.gen += 1;
    const gen: number = Confirm.gen;
    Confirm.opt.title = title;
    Confirm.opt.desc = desc;
    Confirm.opt.confirmText = confirmText;
    Confirm.opt.onOk = onOk;
    Confirm.onOkSnapshot = onOk;      // v5.14：动作快照，确认时用这份
    Confirm.pending = false;
    Confirm.opening = true;
    const opts: promptAction.CustomDialogOptions = {
      builder: builder,
      width: '100%',
      height: '100%',
      backgroundColor: Color.Transparent,
      cornerRadius: 0,
      borderWidth: 0,
      shadow: { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 },
      maskColor: 'rgba(0,0,0,0)',
      autoCancel: false,
      isModal: true,
      onDidDisappear: () => {
        // 系统返回键关掉弹窗时，把 id 清掉，别留成脏值
        // v5.14：只清理「自己那一次」的 id ——
        //   否则旧弹窗的 onDidDisappear 晚到一步，会把新弹窗的 id 抹成 -1，新弹窗就关不掉了。
        if (Confirm.gen === gen) {
          Confirm.id = -1;
        }
      }
    };
    ui.getPromptAction().openCustomDialog(opts).then((id: number) => {
      Confirm.opening = false;
      if (Confirm.pending) {
        Confirm.pending = false;
        Confirm.id = -1;
        try {
          ui.getPromptAction().closeCustomDialog(id);
        } catch (e) {
        }
      } else {
        Confirm.id = id;
      }
    }).catch(() => {
      Confirm.opening = false;
      // 自绘弹窗打不开时的兜底：退回系统确认框，至少别把删除功能弄没了
      Confirm.fallback(ui);
    });
  }

  /** 兜底：系统 AlertDialog（样式差一点，但功能在） */
  private static fallback(ui: UIContext): void {
    const dlg: AlertDialogParamWithButtons = {
      title: Confirm.opt.title,
      message: Confirm.opt.desc,
      autoCancel: true,
      primaryButton: {
        value: Confirm.opt.confirmText,
        fontColor: '#955548',
        action: () => {
          const fn: () => void = Confirm.onOkSnapshot;
          Confirm.onOkSnapshot = () => {};
          fn();
        }
      },
      secondaryButton: { value: '取消', action: () => {} }
    };
    try {
      ui.showAlertDialog(dlg);
    } catch (e) {
      toast(ui, '弹窗没能打开，再点一次试试');
    }
  }

  /** 点确认：先关弹窗，再干活 */
  static confirm(ui: UIContext): void {
    // v5.14：用打开时拍下的那份动作，不是全局的 opt（防止串到别的弹窗）
    const fn: () => void = Confirm.onOkSnapshot;
    Confirm.onOkSnapshot = () => {};
    Confirm.close(ui);
    fn();
  }

  /** 点取消 */
  static cancel(ui: UIContext): void {
    Confirm.onOkSnapshot = () => {};
    Confirm.close(ui);
  }

  static close(ui: UIContext): void {
    if (Confirm.id >= 0) {
      try {
        ui.getPromptAction().closeCustomDialog(Confirm.id);
      } catch (e) {
      }
      Confirm.id = -1;
    } else {
      Confirm.pending = true;
    }
  }
}
