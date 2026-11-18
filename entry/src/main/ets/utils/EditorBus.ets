// 随手记编辑器与外层页面之间的「请关闭编辑器」通道（v5.14 新增）
//
// 为什么需要它：
//   随手记的编辑器是 `views/NotesView.ets` 里的一个居中弹窗，
//   它的开/关状态通过 AppStorage 的 `wb_note_editor_open` 告诉外层 `pages/Index.ets`
//   （外层靠它藏底部导航、系统返回键也靠它判断「先关弹窗」）。
//
//   **但方向是单向的**：外层（Index）只能「把状态改成 false」，
//   改不了 NotesView 内部那些还没落盘的内容。
//   v4.4 之前返回键直接 `AppStorage.set('wb_note_editor_open', false)` ⇒
//   编辑器关了，**刚写的内容一个字都没存**（唯一的不可逆数据丢失路径）。
//
//   v5.14：给外层一条「请随手记自己关」的通道 —— 外层喊一声，
//   NotesView 收到后走它自己的 closeEditor()（先落盘、失败就不关）。
//
// 为什么不用 AppStorage + @Watch：
//   @StorageLink 配 @Watch 在这套 ArkUI V1 里行为不够稳，
//   而且这里只需要一条极窄的命令通道，用一个普通模块级回调最直接、最可控。

type EditorHandler = () => void;

export class EditorBus {
  /** NotesView 注册的「关闭」回调（页面不在时是空实现）。 */
  private static handler: EditorHandler = () => {};

  static setHandler(h: EditorHandler): void {
    EditorBus.handler = h;
  }

  /** 外层请求关闭编辑器（会被 NotesView 接住并走保存流程）。 */
  static requestClose(): void {
    EditorBus.handler();
  }
}
