// 备份到文件 / 从文件恢复（v4.30 新增）
//
// 为什么加这一条：
//   剪贴板只是「临时搬运」，它有三个硬伤 ——
//     1) 系统剪贴板有大小上限（官方没写死数字，几十万字级别就开始不稳）；
//     2) 会被别的复制顶掉（复制一次验证码，备份就没了）；
//     3) 明文躺在全局剪贴板里，别人长按一下输入框就能看到全文。
//   而这个 App 的数据全是纯文本，重度用户一年能攒到 1MB 左右 ——
//   早晚会撞上剪贴板的上限。所以主备份方式改成「导出成一个 .json 文件」。
//
// 权限：这里用的是系统的文件选择器（SAF，Storage Access Framework）。
//   用户在系统界面里自己挑地方，App 拿到的只是用户授权过的那一个 URI，
//   **不需要申请任何权限** —— 这正是 SAF 的设计目的。
//   所以 App 的权限清单仍然是空的，隐私政策不用改，
//   也不用去华为应用市场申请任何东西。
//
// 用到的 API（都在 OpenHarmony SDK 里，不依赖 HMS）：
//   @kit.CoreFileKit → picker.DocumentViewPicker / fileIo
//   @kit.ArkTS       → util.TextDecoder
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export class FileBackup {
  /**
   * 弹出系统「保存文件」对话框，把备份内容写进用户选的位置。
   * @param context UIAbilityContext（picker 需要）
   * @param text    备份内容（纯 JSON 文本）
   * @param fileName 建议的文件名
   * @returns 写入后的文件 URI；用户取消返回空字符串
   */
  static async save(context: common.UIAbilityContext, text: string, fileName: string): Promise<string> {
    const dp: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    opts.newFileNames = [fileName];
    opts.fileSuffixChoices = ['备份文件|.json'];
    let uris: string[] = [];
    try {
      uris = await dp.save(opts);
    } catch (e) {
      if (FileBackup.isCancel(e)) { return ''; }
      const err: Error = e as Error;
      throw err;
    }
    if (!uris || uris.length === 0) { return ''; }
    const uri: string = uris[0];
    // picker 已经把空文件建好了，这里以「读写 + 截断」打开
    let fd: number = -1;
    try {
      const f = await fs.open(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fd = f.fd;
    } catch (e) {
      const err: Error = e as Error;
      throw err;
    }
    try {
      // fs.write 传字符串时默认按 utf-8 编码写入（SDK 原文：encoding 默认 'utf-8'）
      await fs.write(fd, text);
    } catch (e) {
      const err: Error = e as Error;
      throw err;
    } finally {
      await FileBackup.closeQuiet(fd);
    }
    return uri;
  }

  /**
   * 弹出系统「选择文件」对话框，读出用户选中的备份文件内容。
   * @param context UIAbilityContext（picker 需要）
   * @returns 文件文本；用户取消或文件是空的，返回空字符串
   */
  static async pick(context: common.UIAbilityContext): Promise<string> {
    const dp: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['备份文件|.json', '.json'];
    let uris: string[] = [];
    try {
      uris = await dp.select(opts);
    } catch (e) {
      if (FileBackup.isCancel(e)) { return ''; }
      const err: Error = e as Error;
      throw err;
    }
    if (!uris || uris.length === 0) { return ''; }
    const uri: string = uris[0];
    let fd: number = -1;
    try {
      const f = await fs.open(uri, fs.OpenMode.READ_ONLY);
      fd = f.fd;
    } catch (e) {
      const err: Error = e as Error;
      throw err;
    }
    try {
      const st = await fs.stat(fd);
      const size: number = st.size;
      if (size <= 0) { return ''; }
      const buf: ArrayBuffer = new ArrayBuffer(size);
      const n: number = await fs.read(fd, buf);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf, 0, n));
    } catch (e) {
      const err: Error = e as Error;
      throw err;
    } finally {
      await FileBackup.closeQuiet(fd);
    }
  }

  /** 关文件：关不掉就算了，不能因为关文件失败把整次备份搞挂 */
  private static async closeQuiet(fd: number): Promise<void> {
    if (fd < 0) { return; }
    try {
      await fs.close(fd);
    } catch (e) {
      // 忽略
    }
  }

  /** 用户在系统文件选择器里点了「取消」时会抛错，这里识别出来，不要当成失败弹提示 */
  private static isCancel(e: Object): boolean {
    const err = e as BusinessError;
    if (err.code === 13900042) { return true; }
    const msg: string = err.message === undefined ? '' : err.message;
    return msg.toLowerCase().indexOf('cancel') >= 0;
  }
}
