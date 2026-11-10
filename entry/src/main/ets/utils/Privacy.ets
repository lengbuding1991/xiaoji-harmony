// entry/src/main/ets/utils/Privacy.ets
// 隐私同意状态（v4.7 · 上架准备）
//
// 应用市场审核要求：首次启动必须先弹隐私政策，用户同意之后才能使用 App。
// 这个标记不能放在业务数据库里 —— 因为它要在开库之前就要用，
// 所以放在系统偏好设置（preferences）里，一个 App 一个键。
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'wb_prefs';
const KEY_ACCEPTED: string = 'privacy_accepted';

export class Privacy {
  private static pref: preferences.Preferences | null = null;

  /** 打开偏好存储（App 启动时调一次；失败也不影响别的功能） */
  static async init(ctx: common.UIAbilityContext): Promise<void> {
    try {
      Privacy.pref = await preferences.getPreferences(ctx, { name: STORE_NAME });
    } catch (e) {
      Privacy.pref = null;
    }
  }

  /** 用户之前是否已经同意过（同意过就不再弹） */
  static async accepted(): Promise<boolean> {
    try {
      if (Privacy.pref === null) { return false; }
      const v: preferences.ValueType = await Privacy.pref.get(KEY_ACCEPTED, '0');
      if (typeof v === 'string') { return v === '1'; }
      return false;
    } catch (e) {
      return false;
    }
  }

  /** 记录「已同意」 */
  static async accept(): Promise<void> {
    try {
      if (Privacy.pref === null) { return; }
      await Privacy.pref.put(KEY_ACCEPTED, '1');
      await Privacy.pref.flush();
    } catch (e) {
      // 写不进去也不能挡住用户继续用 App
    }
  }
}
