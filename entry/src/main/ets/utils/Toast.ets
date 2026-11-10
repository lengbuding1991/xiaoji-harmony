// entry/src/main/ets/utils/Toast.ets
// 全局 promptAction.showToast 从 API 18 起废弃；必须走 UIContext.getPromptAction()。
import { UIContext, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

export function toast(ui: UIContext, msg: string, bottom: string = '80vp'): void {
  // 顺手打一条日志：Toast 在无障碍树里抓不到，日志是唯一能确认「它到底弹了没」的办法
  hilog.debug(DOMAIN, 'workbench', 'toast: %{public}s', msg);
  try {
    ui.getPromptAction().showToast({ message: msg, duration: 2000, bottom: bottom } as promptAction.ShowToastOptions);
  } catch (e) {
    // Toast 失败不能让页面崩
  }
}

export function toastApiErr(ui: UIContext, e: Object): void {
  const err = e as Error;
  toast(ui, err && err.message ? err.message : '出了点问题');
}
