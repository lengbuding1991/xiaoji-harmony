// entry/src/main/ets/api/Http.ets
// 只用 @ohos.net.http（OpenHarmony 自带的 SystemCapability.Communication.NetStack），
// 纯 OpenHarmony 设备上一定有；不 import 任何 hms/ 能力。
import { http, connection } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TestMode } from '../utils/TestMode';

/** 工作台所有接口出错时都返回这个形状 */
interface ErrorBody {
  error?: string;
}

/**
 * 登录请求体。
 * ArkTS 不允许把对象字面量直接赋给 Record<string, string>
 * （arkts-no-untyped-obj-literals），所以这里要有一个显式声明的 interface。
 */
interface LoginBody {
  password: string;
  confirm?: string;
}

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

/**
 * PATCH 在 RequestMethod 枚举里是 API 26 才声明的成员（见开发文档 2.3.3）。
 * 不引用该成员、只把字符串字面量强转到「枚举类型」——枚举类型本身 API 6 就有，
 * 所以 compatibleSdkVersion 不用抬到 26。P0 第一件事就是实测这样真能发出 PATCH。
 */
const PATCH: http.RequestMethod = 'PATCH' as http.RequestMethod;

export class Http {
  private static cookie: string = '';
  // 服务器地址不再让用户手填：启动时按候选列表自动探测，第一个通的就用。
  // 探到的结果会持久化，下次直接复用；换环境去「设置」页改一次即可。
  private static baseUrl: string = 'http://10.0.2.2:3100';
  private static pref: preferences.Preferences | null = null;

  /**
   * 候选地址，按优先级排列。三个场景分别对应：
   * - 10.0.2.2  Android 模拟器访问宿主机的约定地址（鸿蒙模拟器不认，留着也不碍事）
   * - 127.0.0.1 走了 `hdc rport tcp:3100 tcp:3100` 反向端口转发时可用
   * - 电脑的局域网地址 / mDNS 名字  真机与电脑在同一 Wi-Fi 时用这个连电脑
   * - 线上域名  不接电脑、直接用 NAS 上的正式服务时走这里
   * 另外启动时还会扫一遍手机所在网段（见 scanLanForWorkbench），
   * 这样电脑的 IP 变了也不用改代码。
   */
  static candidates(): string[] {
    const list: string[] = [];
    const saved: string = Http.getSavedUrl();
    if (saved.length > 0) {
      list.push(saved);
    }
    list.push('http://127.0.0.1:3100');
    list.push('http://lengzhubudingdeMac-mini.local:3100');
    list.push('http://192.168.0.102:3100');
    list.push('http://10.0.2.2:3100');
    list.push('https://workbench.lbuding.com');
    return list;
  }

  /** 当前地址是不是「本机 / 局域网」——测试密码只往这类地址发 */
  static isLocalBaseUrl(): boolean {
    const u: string = Http.baseUrl.toLowerCase();
    if (u.indexOf('127.0.0.1') >= 0 || u.indexOf('localhost') >= 0 || u.indexOf('10.0.2.2') >= 0) {
      return true;
    }
    if (u.indexOf('.local') >= 0) {
      return true;
    }
    if (u.indexOf('://10.') >= 0 || u.indexOf('://192.168.') >= 0) {
      return true;
    }
    return false;
  }

  /**
   * 手机自己所在网段的 IPv4。
   * 只认 Wi-Fi / 有线这类局域网接口：扫描局域网这件事在蜂窝网上没意义，
   * 而且蜂窝网会慢得离谱。
   */
  private static localIPv4(): string {
    try {
      const nets: connection.NetHandle[] = connection.getAllNetsSync();
      for (let i = 0; i < nets.length; i++) {
        const props: connection.ConnectionProperties = connection.getConnectionPropertiesSync(nets[i]);
        const name: string = props.interfaceName ?? '';
        // wlan = Wi-Fi；eth = 有线；其它（rmnet / cellular）跳过
        if (name.indexOf('wlan') < 0 && name.indexOf('wifi') < 0 && name.indexOf('eth') < 0) {
          continue;
        }
        const links: connection.LinkAddress[] = props.linkAddresses;
        for (let j = 0; j < links.length; j++) {
          const addr: connection.NetAddress = links[j].address;
          // family 1 = IPv4；跳过回环
          if (addr.family !== 1 || !addr.address || addr.address.indexOf('127.') === 0) {
            continue;
          }
          return addr.address;
        }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  /**
   * 扫本机所在 /24 网段，找出开着 3100 且响应 /api/health 的那台（一般就是电脑上的 dev server）。
   * 分批并发：每批 48 个、每个超时 600ms，最坏 6 批 ≈ 3.6 秒。
   */
  private static async scanLanForWorkbench(): Promise<string> {
    const me: string = Http.localIPv4();
    if (me.length === 0) {
      return '';
    }
    const parts: string[] = me.split('.');
    if (parts.length !== 4) {
      return '';
    }
    const prefix: string = `${parts[0]}.${parts[1]}.${parts[2]}.`;
    const batch: number = 48;
    for (let start = 1; start <= 254; start += batch) {
      const end: number = Math.min(start + batch - 1, 254);
      const jobs: Array<Promise<string>> = [];
      for (let h = start; h <= end; h++) {
        if (`${h}` === parts[3]) {
          continue;
        }
        jobs.push(Http.probeRoot(`${prefix}${h}:3100`, 600));
      }
      const hits: string[] = await Promise.all(jobs);
      for (let k = 0; k < hits.length; k++) {
        if (hits[k].length > 0) {
          return hits[k];
        }
      }
    }
    return '';
  }

  private static getSavedUrl(): string {
    const p = Http.pref;
    if (!p) {
      return '';
    }
    try {
      return p.getSync('base_url_v2', '') as string;
    } catch (e) {
      return '';
    }
  }

  /**
   * 启动时调一次：逐个候选打 /api/health（超时压到 2 秒，避免拖慢启动）。
   * 顺序：手动指定的 → 固定候选 → 扫局域网 → 线上正式服务。
   * 全不通就保持当前值，后续请求照常抛错，错误信息里带地址便于判断打到了哪。
   */
  static async autoDetect(): Promise<boolean> {
    const list: string[] = Http.candidates();
    for (let i = 0; i < list.length - 1; i++) {
      const root: string = list[i];
      const hit: string = await Http.probeRoot(root);
      if (hit.length > 0) {
        Http.setBaseUrl(hit);
        return true;
      }
    }
    // 真机连电脑：电脑 IP 变了也能自己找到
    const lan: string = await Http.scanLanForWorkbench();
    if (lan.length > 0) {
      Http.setBaseUrl(lan);
      return true;
    }
    // 最后一个是线上正式服务，放最后兜底
    const last: string = list[list.length - 1];
    const hitLast: string = await Http.probeRoot(last);
    if (hitLast.length > 0) {
      Http.setBaseUrl(hitLast);
      return true;
    }
    return false;
  }

  /** 探一个地址能不能通（GET /api/health，免登录）。通了返回地址，不通返回空串。 */
  private static async probeRoot(root: string, timeout: number = 2000): Promise<string> {
    const header: Record<string, string> = { 'Content-Type': 'application/json' };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: timeout,
      readTimeout: timeout
    };
    const req = http.createHttp();
    try {
      const resp = await req.request(root + '/api/health', options);
      req.destroy();
      const code = resp.responseCode as number;
      return code >= 200 && code < 300 ? root : '';
    } catch (e) {
      req.destroy();
      return '';
    }
  }

  /** 应用启动时调一次（EntryAbility.onCreate 里）：打开偏好存储、恢复 baseUrl 和 cookie */
  static init(ctx: common.Context): void {
    // preferences 的同步方法在首次建库 / 文件损坏时会抛异常（ArkTS 编译期会告警）。
    // 这里必须兜住：持久化失败只是「下次要重新登录」，绝不能让 Ability 启动崩掉。
    const opt: preferences.Options = { name: 'wb_prefs' };
    try {
      Http.pref = preferences.getPreferencesSync(ctx, opt);
      // 用 base_url_v2 做一次性迁移：老版本存过线上域名的，这里直接忽略，
      // 让新的本地默认值生效；用户在设置页改过之后才会被持久化回来。
      const saved: string = Http.pref.getSync('base_url_v2', '') as string;
      if (saved.length > 0) {
        Http.baseUrl = saved;
      }
      Http.cookie = Http.pref.getSync('cookie', '') as string;
      // 测试模式（免密码进入）的开关也跟着持久化，默认开
      const tm: boolean = Http.pref.getSync('test_mode', true) as boolean;
      TestMode.enabled = tm;
      // 测试密码也持久化，设置页里可以改
      const tp: string = Http.pref.getSync('test_password', '') as string;
      if (tp.length > 0) {
        TestMode.password = tp;
      }
      // 连续失败次数也要记住：避免 App 反复重启把服务端锁 10 分钟
      const fc: number = Http.pref.getSync('test_fails', 0) as number;
      TestMode.failCount = fc;
    } catch (e) {
      Http.pref = null;
    }
  }

  /** 开关「免密码进入（测试模式）」 */
  static setTestMode(on: boolean): void {
    TestMode.enabled = on;
    if (on) {
      TestMode.failCount = 0;
    }
    if (Http.pref) {
      const p = Http.pref;
      Http.persist(() => {
        p.putSync('test_mode', on);
        p.putSync('test_fails', TestMode.failCount);
        p.flush();
      });
    }
  }

  /** 统一的持久化封装：把「可能抛异常」收在一处，调用点全都变干净 */
  private static persist(action: () => void): void {
    try {
      action();
    } catch (e) {
      // 落盘失败不影响内存态
    }
  }

  /** 改测试密码（设置页用） */
  static setTestPassword(pwd: string): void {
    TestMode.password = pwd;
    TestMode.failCount = 0;
    if (Http.pref) {
      const p = Http.pref;
      Http.persist(() => {
        p.putSync('test_password', pwd);
        p.putSync('test_fails', 0);
        p.flush();
      });
    }
  }

  /** 记一次测试登录失败（连续 3 次就停手，避免触发服务端 10 分钟锁） */
  static markTestFail(): void {
    TestMode.markFail();
    if (Http.pref) {
      const p = Http.pref;
      Http.persist(() => {
        p.putSync('test_fails', TestMode.failCount);
        p.flush();
      });
    }
  }

  /** 测试登录成功，清零失败计数 */
  static markTestOk(): void {
    TestMode.markOk();
    if (Http.pref) {
      const p = Http.pref;
      Http.persist(() => {
        p.putSync('test_fails', 0);
        p.flush();
      });
    }
  }

  static setBaseUrl(url: string): void {
    Http.baseUrl = url.replace(/\/+$/, '');
    if (Http.pref) {
      const p = Http.pref;
      const value = Http.baseUrl;
      Http.persist(() => {
        p.putSync('base_url_v2', value);
        p.flush();
      });
    }
  }

  static getBaseUrl(): string {
    return Http.baseUrl;
  }

  /**
   * 连不上时的提示。手机连电脑测的时候，最常见的原因不是 App 有问题，
   * 而是电脑上的 dev server 没开 —— 只说「连不上」用户根本不知道该干嘛。
   */
  static unreachableHint(): string {
    const url: string = Http.baseUrl;
    if (url.indexOf('192.168.') >= 0 || url.indexOf('.local') >= 0 || url.indexOf('10.0.2.2') >= 0) {
      return `连不上电脑上的工作台（${url}）。\n请先在电脑上启动：cd 个人工作台 && pnpm dev\n（手机和电脑要连同一个 Wi-Fi）`;
    }
    if (url.indexOf('127.0.0.1') >= 0 || url.indexOf('localhost') >= 0) {
      return `连不上本机的工作台（${url}）。\n请先启动 dev server，或在设置里改成电脑的局域网地址`;
    }
    return `连不上工作台（${url}）`;
  }

  static isLoggedIn(): boolean {
    return Http.cookie.length > 0;
  }

  /**
   * HttpResponse.cookies 是服务端返回的原始 Set-Cookie 串，不是结构化数组。
   * 千万别用 split(',') 或 split(';') 去切——
   *   Expires=Thu, 01 Jan 2026 00:00:00 GMT  里有逗号
   *   Path=/; HttpOnly; SameSite=Lax          里有分号
   * 都会把 cookie 值切坏。直接按名字正则捞最稳。
   * wb_session 的值是「<过期时间戳>.<签名>」，只有字母数字和点，遇不到上面那几个分隔符。
   */
  /**
   * 从各种形状里把 wb_session 捞出来。
   *
   * 服务端下发的是标准 Set-Cookie：
   *   wb_session=<时间戳>.<签名>; Path=/; Expires=Sun, 08 Nov 2026 00:56:34 GMT; Max-Age=86400; HttpOnly; SameSite=lax
   * 有三个坑：
   *   1. Expires 里带逗号 → 不能用 split(',') 切
   *   2. 属性之间用分号 → 不能用 split(';')[0] 直接取（万一 cookie 顺序变了就取错）
   *   3. HttpResponse.cookies 只有在 SDK 解析成功时才有内容，
   *      某些情况下只有 resp.header['set-cookie'] 里有
   * 所以：先用正则按名字捞；捞不到再看 header；都捞不到就整个字符串当成裸值试一次。
   */
  private static pickSessionCookie(raw: string): string {
    if (!raw) {
      return '';
    }
    const m = /wb_session=([^;\s,]+)/.exec(raw);
    if (m && m[1]) {
      return `wb_session=${m[1]}`;
    }
    // 兜底一：整段就是 cookie 值本身（没有 wb_session= 前缀）
    const bare = /^\s*([0-9]{10,}\.[A-Za-z0-9_\-]+)\s*$/.exec(raw);
    if (bare && bare[1]) {
      return `wb_session=${bare[1]}`;
    }
    return '';
  }

  /** 把响应里的 set-cookie 头拼成一段可检索的文本（可能是 string，也可能是 string[]） */
  private static headerCookieText(header: Object): string {
    let text = '';
    try {
      const h = header as Record<string, string>;
      const v = h['set-cookie'];
      if (typeof v === 'string') {
        text = v;
      } else if (Array.isArray(v)) {
        const arr = v as string[];
        for (let i = 0; i < arr.length; i++) {
          text = text + '\n' + arr[i];
        }
      }
    } catch (e) {
      // header 结构异常就当没有，不影响主流程
    }
    return text;
  }

  private static saveCookies(raw: string): void {
    if (!raw) {
      return;
    }
    const value = Http.pickSessionCookie(raw);
    if (!value) {
      return;
    }
    Http.cookie = value;
    if (Http.pref) {
      const p = Http.pref;
      Http.persist(() => {
        p.putSync('cookie', value);
        p.flush();
      });
    }
  }

  /**
   * 登录一次，把会话 cookie 拿到手。
   * 测试模式下 App 用它免密码进入；正式模式下用户手输密码时也走这里。
   *
   * ⚠️ 这里必须用 requestOnce，不能用 post()：post() 在 401 时会自动重登，
   *    登录接口自己返回 401 就会无限递归。
   */
  static async login(password: string, confirm?: string): Promise<void> {
    const body: LoginBody = { password: password, confirm: confirm };
    await Http.requestOnce<Record<string, boolean>>('POST' as http.RequestMethod, '/api/auth', body);
    if (!Http.isLoggedIn()) {
      throw new ApiError('登录成功但没拿到会话，请重试', 401);
    }
  }

  /**
   * 写操作撞到 401 时自动重登一次再重试。
   * 场景：App 开着放了很久，cookie 过期（服务端 24 小时）；或者用户在工作台那边改了密码。
   */
  static async ensureSession(): Promise<boolean> {
    if (Http.cookie.length > 0) {
      return true;
    }
    if (!TestMode.enabled || !Http.isLocalBaseUrl()) {
      return false;
    }
    try {
      await Http.login(TestMode.password);
      return true;
    } catch (e) {
      return false;
    }
  }

  static clearCookie(): void {
    Http.cookie = '';
    if (Http.pref) {
      const p = Http.pref;
      Http.persist(() => {
        p.deleteSync('cookie');
        p.flush();
      });
    }
  }

  /** 真正发一次请求（不处理 401 重试） */
  private static async requestOnce<T>(method: http.RequestMethod, path: string, body?: Object): Promise<T> {
    const header: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (Http.cookie) {
      header['Cookie'] = Http.cookie;
    }

    const options: http.HttpRequestOptions = {
      method: method,
      header: header,
      expectDataType: http.HttpDataType.STRING,  // JSON 直接拿到字符串，不用 TextDecoder
      usingCache: false,                         // 默认 true！会把任务列表缓存住，必须关
      connectTimeout: 10000,
      readTimeout: 20000
    };
    // SDK 注释明确：无 body 时不要传 extraData，更不要传空字符串
    if (body !== undefined) {
      options.extraData = JSON.stringify(body);
    }

    const req = http.createHttp();
    let resp: http.HttpResponse;
    try {
      resp = await req.request(Http.baseUrl + path, options);
    } catch (e) {
      // NAS 重启 / 没网 / 域名解析失败 / 权限没声明，全归到这里
      req.destroy();
      throw new ApiError(Http.unreachableHint(), 0);
    }
    // @ohos.net.http.d.ts 开头专门警告：不调 destroy() 会内存泄漏。两条路径都要走。
    req.destroy();

    // 登录 / 续期时服务端会给新 cookie。
    // 两个来源都要看：HttpResponse.cookies 只在 SDK 解析成功时才有内容，
    // 某些情况下 set-cookie 只出现在响应头里。少看一个就会变成「登录成功了但一直 401」。
    Http.saveCookies(resp.cookies);
    Http.saveCookies(Http.headerCookieText(resp.header));

    // expectDataType=STRING 且响应为 JSON 时，result 就是字符串
    const text = typeof resp.result === 'string' ? resp.result : '';
    const code = resp.responseCode as number;   // 注意：这里叫 responseCode，不叫 statusCode

    if (code < 200 || code >= 300) {
      let msg = `请求失败（${code}）`;
      if (code === 401) {
        msg = '登录已过期，请重新登录';
      } else {
        try {
          const obj = JSON.parse(text) as ErrorBody;
          if (obj.error) {
            msg = obj.error;
          }
        } catch (e) {
          // 不是 JSON，用默认文案
        }
      }
      throw new ApiError(msg, code);
    }

    if (!text || text.length === 0) {
      // ArkTS 不允许 `{} as T`（arkts-no-untyped-obj-literals）：对象字面量必须有显式类型。
      // 用 JSON.parse 拿到一个 Object 再转，和下面正常路径的写法保持一致。
      return JSON.parse('{}') as T;   // DELETE 等无响应体的接口
    }
    return JSON.parse(text) as T;
  }

  /**
   * 发请求；遇到 401 时，测试模式下自动重登一次再重试。
   * 场景：cookie 过期（服务端 24 小时）、或用户在工作台那边改了密码。
   */
  static async request<T>(method: http.RequestMethod, path: string, body?: Object): Promise<T> {
    try {
      return await Http.requestOnce<T>(method, path, body);
    } catch (e) {
      // ArkTS 只允许 throw 明确类型的异常（arkts-limited-throw），所以必须转成 ApiError。
      const err: ApiError = e as ApiError;
      if (err.status !== 401) {
        throw err;
      }
      Http.clearCookie();
      // 只有本机 / 局域网才用测试密码重登，线上服务绝不试（会触发风控锁 10 分钟）
      if (!TestMode.canTry() || !Http.isLocalBaseUrl()) {
        throw err;
      }
      try {
        await Http.login(TestMode.password);
      } catch (e2) {
        Http.markTestFail();
        throw err;
      }
      Http.markTestOk();
      return await Http.requestOnce<T>(method, path, body);
    }
  }

  static get<T>(path: string): Promise<T> {
    return Http.request<T>(http.RequestMethod.GET, path);
  }
  static post<T>(path: string, body?: Object): Promise<T> {
    return Http.request<T>(http.RequestMethod.POST, path, body);
  }
  static patch<T>(path: string, body?: Object): Promise<T> {
    return Http.request<T>(PATCH, path, body);
  }
  static del<T>(path: string): Promise<T> {
    return Http.request<T>(http.RequestMethod.DELETE, path);
  }
  /** 少数接口（如 DELETE /api/reviews）要求把 id 放在请求体里 */
  static delBody<T>(path: string, body: Object): Promise<T> {
    return Http.request<T>(http.RequestMethod.DELETE, path, body);
  }
}
