// entry/src/main/ets/utils/TestMode.ets
//
// 「测试模式」：跳过密码页直接进主界面。
//
// 为什么要它：工作台的所有数据接口（/api/tasks、/api/notes…）在服务端都会先
// requireAuth()，也就是说光在 App 里不弹密码框是没有用的——写操作一律 401。
// 所以这里做的是：App 侧在启动时自己拿已知密码登一次，把会话 cookie 拿到手，
// 用户看到的仍然是「不用输密码」，但底层读写都是正常走鉴权。
//
// ⚠️ 测试密码只往「本机 / 局域网」地址发（见 Http.isLocalBaseUrl），
//    绝不会拿去试线上 NAS 的正式服务——那边密码不同，连试会触发
//    「同 IP 10 分钟错 6 次锁 10 分钟」。
//
// 正式发布前把 enabled 关掉（或在设置页关掉）即可恢复密码登录。

export class TestMode {
  /** 是否启用免密码进入。启动时由 Http.init 从偏好存储恢复，默认开。 */
  static enabled: boolean = true;

  /**
   * 本地工作台的测试密码。
   * 可以改（设置页里能填），会存进偏好存储。
   * 正式上线前把 enabled 关掉即可恢复密码登录。
   */
  // 公网仓库里不保留本地开发库的测试口令；本机原始值见 开发文档 §「测试模式」
  static password: string = 'REDACTED_IN_PUBLIC_REPO';

  /** 自动登录连续失败几次后就不再试了，避免把服务端锁 10 分钟 */
  static failCount: number = 0;

  static readonly maxFails: number = 3;

  /** 还能不能继续用测试密码试 */
  static canTry(): boolean {
    return TestMode.enabled && TestMode.failCount < TestMode.maxFails;
  }

  static markFail(): void {
    TestMode.failCount = TestMode.failCount + 1;
  }

  static markOk(): void {
    TestMode.failCount = 0;
  }
}
