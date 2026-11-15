import { insightIntent, InsightIntentExecutor } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

/**
 * v4.33：Intents Kit「功能搜索」执行器（路径 2）
 *
 * 作用：让用户在**桌面下拉搜索 / 小艺**里搜「记笔记」「日程」「待办」这类功能词时，
 * 能直接搜到小记，并点击结果**直达 App 内的对应页面**（不是只打开 App 首页）。
 *
 * 官方依据：《功能搜索方案》（5.1.0(18) 起）
 *   https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/intents-skill-all-rec-function-search
 *   意图名称：JumpFunctionPage（端侧前台意图调用）
 *   声明文件：src/main/resources/base/profile/insight_intent.json（整个工程只能有一份）
 *
 * 小记是**单页 + 内部 state 切换**架构（没有 router.pushUrl，只有一个 pages/Index），
 * 所以这里复用已有的**深链通道**：写 AppStorage 'wb_open_page' → Index.ets 的
 * @StorageLink/@Watch 与 onPageShow 收到后调用 go(page) 切页。
 * 两条路径都覆盖：
 *   · App 已经在前台 ⇒ @Watch 立刻触发，直接切页；
 *   · App 冷启动 ⇒ loadContent('pages/Index') 之后 aboutToAppear/onPageShow 补跳。
 */
export default class InsightIntentExecutorImpl extends InsightIntentExecutor {
  private static readonly JUMP_FUNCTION_PAGE: string = 'JumpFunctionPage';

  /** 合法页面白名单（与 Index.ets 的 go() 认识的 key 完全一致） */
  private static readonly PAGES: string[] = ['home', 'tasks', 'calendar', 'notes'];

  /**
   * override：前台 UIAbility 意图执行
   */
  onExecuteInUIAbilityForegroundMode(name: string, param: Record<string, Object>,
    pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    if (name === InsightIntentExecutorImpl.JUMP_FUNCTION_PAGE) {
      return this.jumpFunctionPage(param, pageLoader);
    }
    hilog.error(DOMAIN, 'workbench', 'insight intent unknown: %{public}s', name);
    const data: insightIntent.ExecuteResult = {
      code: -1,
      result: {
        message: 'unknown intent'
      }
    };
    return Promise.resolve(data);
  }

  /**
   * 实现「跳到指定功能页」
   */
  private jumpFunctionPage(param: Record<string, Object>,
    pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    const raw: Object | undefined = param['pageId'];
    const pageId: string = (typeof raw === 'string') ? raw : '';
    if (pageId.length === 0 || !InsightIntentExecutorImpl.PAGES.includes(pageId)) {
      hilog.error(DOMAIN, 'workbench', 'insight intent bad pageId: %{public}s', pageId);
      const data: insightIntent.ExecuteResult = {
        code: -1,
        result: {
          message: 'pageId type error'
        }
      };
      return Promise.resolve(data);
    }

    // ① 先写 AppStorage：App 已在运行时，Index 的 @Watch 会立刻切页（不需要 loadContent）
    try {
      AppStorage.setOrCreate<string>('wb_open_page', pageId);
      // nonce 递增：保证「连续两次搜同一个功能」也能触发（值变了 @Watch 才回调）
      const nonce: number = AppStorage.get<number>('wb_dl_nonce') ?? 0;
      AppStorage.setOrCreate<number>('wb_dl_nonce', nonce + 1);
    } catch (e) {
      hilog.error(DOMAIN, 'workbench', 'insight intent set AppStorage failed: %{public}s',
        (e as Error).message ?? '');
    }

    // ② 再确保页面已加载：App 冷启动时必须 loadContent 一次
    return pageLoader.loadContent('pages/Index')
      .then(() => {
        hilog.info(DOMAIN, 'workbench', 'insight intent jump ok: %{public}s', pageId);
        const data: insightIntent.ExecuteResult = {
          code: 0,
          result: {
            message: 'Intent execute success'
          }
        };
        return data;
      })
      .catch((err: Error) => {
        // App 已经在前台时 loadContent 可能失败（窗口已有内容）；
        // 这时 ① 已经把 wb_open_page 写好，Index 的 @Watch 已经切过去了 ⇒ 仍然算成功
        hilog.error(DOMAIN, 'workbench', 'insight intent loadContent failed: %{public}s',
          err.message ?? '');
        const data: insightIntent.ExecuteResult = {
          code: 0,
          result: {
            message: 'Intent execute success'
          }
        };
        return data;
      });
  }
}
