// entry/src/main/ets/db/Boot.ets
// 本地库的启动闸门：App 起来时「开库 + 建表 + 铺示例数据」只做一次，
// 页面等这个闸门开了再去读数据。
//
// 为什么要有这个闸门：开库是异步的（要建 17 张表 + 索引），
// 而页面的 aboutToAppear 比它早。如果不等，页面读到的就是一张还没建好的空库 ——
// 表现是「打开 App 什么都是 0」，但数据其实在，几秒后才出现。
// 有了这个闸门：页面 await Boot.when() 之后拿到的永远是「能用的库」。
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Db } from './Db';
import { Repo } from './Repo';

export class Boot {
  private static ready: Promise<void> = Promise.resolve();
  private static started: boolean = false;
  private static err: string = '';
  private static ctx: common.Context | null = null;

  /** App 启动时调一次（EntryAbility.onCreate） */
  static start(ctx: common.Context): void {
    if (Boot.started) { return; }
    Boot.started = true;
    Boot.ctx = ctx;
    Boot.ready = Boot.init(ctx).then(() => {
      Boot.err = '';
    }).catch((e: Error) => {
      // v4.4：不再假装吞错 —— 把原因记下来，页面据此显示「打不开 + 重试」，
      // 而不是永远卡在「正在打开本地数据…」。
      Boot.err = e.message ?? '未知错误';
      hilog.error(0x0000, 'workbench', 'boot failed: %{public}s', Boot.err);
    });
  }

  /** 页面等这个：库和示例数据都就绪了（开库失败时也会 resolve，但 Boot.error() 有值） */
  static when(): Promise<void> {
    return Boot.ready;
  }

  /** 开库失败的说明（空字符串 = 没问题） */
  static error(): string {
    return Boot.err;
  }

  /** 开库失败后重试 */
  static retry(): void {
    const c: common.Context | null = Boot.ctx;
    if (c === null) { return; }
    Boot.err = '';
    Boot.ready = Boot.init(c).then(() => {
      Boot.err = '';
    }).catch((e: Error) => {
      Boot.err = e.message ?? '未知错误';
      hilog.error(0x0000, 'workbench', 'boot retry failed: %{public}s', Boot.err);
    });
  }

  private static async init(ctx: common.Context): Promise<void> {
    await Db.open(ctx);
    await Repo.seedIfEmpty();
  }
}
