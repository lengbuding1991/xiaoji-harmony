# 归档：联网层（v4.0 起不进编译图）

这三个文件是 v3.0「联网版」留下的：

| 文件 | 原来干什么 |
|---|---|
| `Http.ets` | `@ohos.net.http` 封装：cookie 管理、超时、错误文案、局域网自动探测、测试模式自动登录 |
| `Endpoints.ets` | API 路径常量表 |
| `TestMode.ets` | 测试模式（免密码进 App，只对本机 / 局域网地址生效） |

## 为什么归档

v4.0 起 App **完全离线**：数据存在手机本机 `workbench.db`，`module.json5` 里连
`ohos.permission.INTERNET` 都撤掉了。这三个文件没有任何地方引用，
而且**留在 `entry/src/main/ets/` 里会被 hvigor 扫进工程**（孤儿 `.ets` 不会进编译图，
但会让工程目录看起来还是联网的，容易误解），所以整体移到工程根目录的这个文件夹。

> 移动它们**不影响编译**：`CompileArkTS` 只沿 `main_pages.json` 里注册的页面追 import。

## 以后要做「和网页版同步」怎么捡回来

1. 把这三个文件挪回 `entry/src/main/ets/api/` 与 `utils/`；
2. `module.json5` 加回 `ohos.permission.INTERNET`；
3. 新写一层 `db/Sync.ets`：把 `Repo` 的写操作**双写**到本地库 + 服务器，
   读操作以本地库为准、后台再拉服务器增量；
4. `Store` 里那 22 处 `Repo.xxx` 调用**一行都不用改**——这就是当初把
   `Store`（业务）和 `Repo`（数据源）分开的原因。

`Repo` 的方法名和返回结构是照着这批 HTTP 接口设计的，所以同步层写起来会很顺。
