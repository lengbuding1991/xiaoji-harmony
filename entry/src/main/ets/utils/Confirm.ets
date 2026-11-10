// entry/src/main/ets/utils/Confirm.ets
// v2.9：删除确认统一入口（自绘弹窗，不用系统 AlertDialog）。
//
// 为什么绕这一圈：删除按钮有两种位置——页面里（记录灵感）和 bindSheet 弹层里（任务/日程）。
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
    Confirm.opt.title = title;
    Confirm.opt.desc = desc;
    Confirm.opt.confirmText = confirmText;
    Confirm.opt.onOk = onOk;
    Confirm.pending = false;
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
        Confirm.id = -1;
      }
    };
    ui.getPromptAction().openCustomDialog(opts).then((id: number) => {
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
          const fn: () => void = Confirm.opt.onOk;
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
    const fn: () => void = Confirm.opt.onOk;
    Confirm.close(ui);
    fn();
  }

  /** 点取消 */
  static cancel(ui: UIContext): void {
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
