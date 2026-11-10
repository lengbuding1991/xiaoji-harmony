// entry/src/main/ets/db/Db.ets
// 本地数据库：HarmonyOS RDB（@ohos.data.relationalStore）。
// v4.0 起 App 完全离线 —— 所有数据存在手机本地的 workbench.db，不连任何服务器。
// 表结构与「个人工作台」lib/db.ts 的 SCHEMA 一一对应，方便导出 / 导入 / 将来同步。
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const DB_NAME = 'workbench.db';

export class Db {
  private static store: relationalStore.RdbStore | null = null;
  private static opening: Promise<void> | null = null;
  private static opened: boolean = false;

  /** 建表语句：字段名、可空性都和工作台 SCHEMA 一致 */
  private static readonly DDL: string[] = [
    `CREATE TABLE IF NOT EXISTS project (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color TEXT NOT NULL DEFAULT '#9B8AE6',
      area TEXT NOT NULL DEFAULT 'work',
      status TEXT NOT NULL DEFAULT 'active',
      note TEXT NOT NULL DEFAULT '',
      sort INTEGER NOT NULL DEFAULT 0,
      target_date TEXT,
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS task (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'todo',
      priority TEXT NOT NULL DEFAULT 'med',
      area TEXT NOT NULL DEFAULT 'work',
      project_id INTEGER,
      due_date TEXT,
      scheduled_start TEXT,
      scheduled_end TEXT,
      estimate_min INTEGER,
      done_at TEXT,
      sort INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      project TEXT NOT NULL DEFAULT '',
      tags TEXT NOT NULL DEFAULT '',
      repeat_rule TEXT NOT NULL DEFAULT 'none',
      remind_min INTEGER
    )`,
    `CREATE TABLE IF NOT EXISTS event (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      start_at TEXT NOT NULL,
      end_at TEXT,
      all_day INTEGER NOT NULL DEFAULT 0,
      location TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      repeat_rule TEXT NOT NULL DEFAULT 'none',
      remind_min INTEGER
    )`,
    `CREATE TABLE IF NOT EXISTS note (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL DEFAULT '',
      pinned INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      tags TEXT NOT NULL DEFAULT '',
      archived INTEGER NOT NULL DEFAULT 0,
      project_id INTEGER
    )`,
    `CREATE TABLE IF NOT EXISTS note_task (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL,
      task_id INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS task_event (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id INTEGER NOT NULL,
      event_id INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS review (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'daily',
      did TEXT NOT NULL DEFAULT '',
      stuck TEXT NOT NULL DEFAULT '',
      tomorrow TEXT NOT NULL DEFAULT '',
      summary TEXT NOT NULL DEFAULT '',
      ai_generated INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS setting (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL DEFAULT ''
    )`,
    `CREATE TABLE IF NOT EXISTS habit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      color TEXT NOT NULL DEFAULT '#3AC8C2',
      sort INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS habit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      habit_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      created_at TEXT NOT NULL
    )`,
    `CREATE INDEX IF NOT EXISTS idx_task_status ON task (status)`,
    `CREATE INDEX IF NOT EXISTS idx_task_due ON task (due_date)`,
    `CREATE INDEX IF NOT EXISTS idx_event_start ON event (start_at)`,
    `CREATE INDEX IF NOT EXISTS idx_note_archived ON note (archived)`,
    `CREATE INDEX IF NOT EXISTS idx_habit_log ON habit_log (habit_id, date)`,
    `CREATE INDEX IF NOT EXISTS idx_note_task ON note_task (note_id, task_id)`
  ];

  /** 打开（或建好）本地库。重复调用安全：并发时共用同一个 Promise */
  static async open(ctx: common.Context): Promise<void> {
    if (Db.opened) { return; }
    if (Db.opening !== null) { await Db.opening; return; }
    Db.opening = Db.init(ctx);
    try {
      await Db.opening;
    } finally {
      Db.opening = null;
    }
  }

  private static async init(ctx: common.Context): Promise<void> {
    try {
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S2
      };
      Db.store = await relationalStore.getRdbStore(ctx, config);
      for (let i = 0; i < Db.DDL.length; i++) {
        await Db.store.executeSql(Db.DDL[i]);
      }
      Db.opened = true;
      hilog.debug(DOMAIN, 'workbench', 'local db ready: %{public}s', DB_NAME);
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, 'workbench', 'open db failed: %{public}s', err.message ?? 'unknown');
      throw err;
    }
  }

  static isReady(): boolean {
    return Db.opened && Db.store !== null;
  }

  /** 必须在 open() 之后调用 */
  private static need(): relationalStore.RdbStore {
    const s = Db.store;
    if (s === null) {
      throw new Error('数据库还没打开');
    }
    return s;
  }

  /** ── 事务：把一批写操作包起来，中途出错整体回滚 ──
   *  v4.4：备份恢复用它保证「要么全成功，要么原数据一条不动」。
   */
  static async beginTx(): Promise<void> {
    const s: relationalStore.RdbStore = await Db.ensure();
    try {
      s.beginTransaction();
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, 'workbench', 'beginTransaction failed: %{public}s', err.message ?? 'unknown');
      throw err;
    }
  }

  static async commitTx(): Promise<void> {
    const s: relationalStore.RdbStore = await Db.ensure();
    try {
      s.commit();
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, 'workbench', 'commit failed: %{public}s', err.message ?? 'unknown');
      throw err;
    }
  }

  static async rollbackTx(): Promise<void> {
    const s: relationalStore.RdbStore = await Db.ensure();
    try {
      s.rollBack();
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, 'workbench', 'rollback failed: %{public}s', err.message ?? 'unknown');
    }
  }

  /** 拿一个可用的 store：如果正在开库就等它开完（避免竞态读到空库） */
  private static async ensure(): Promise<relationalStore.RdbStore> {
    if (!Db.opened && Db.opening !== null) {
      try {
        await Db.opening;
      } catch (e) {
        // 开库失败：交给下面的 need() 抛明确错误
      }
    }
    return Db.need();
  }

  /** 执行写语句 / DDL */
  static async exec(sql: string, args?: Array<relationalStore.ValueType>): Promise<void> {
    const s = await Db.ensure();
    try {
      if (args !== undefined && args.length > 0) {
        await s.executeSql(sql, args);
      } else {
        await s.executeSql(sql);
      }
    } catch (e) {
      // 出错就往上抛（Repo / Store 层统一 try/catch），但统一成 Error 类型
      const err: Error = e as Error;
      throw err;
    }
  }

  /** 查询，返回 ResultSet（调用方负责 close） */
  static async query(sql: string, args?: Array<relationalStore.ValueType>): Promise<relationalStore.ResultSet> {
    const s = await Db.ensure();
    try {
      if (args !== undefined && args.length > 0) {
        return await s.querySql(sql, args);
      }
      return await s.querySql(sql);
    } catch (e) {
      const err: Error = e as Error;
      throw err;
    }
  }

  /**
   * 执行 INSERT 并拿回自增 id。
   *
   * 坑：`last_insert_rowid()` 是**按连接**算的，而 RDB 的 executeSql / querySql
   * 可能落在连接池里的另一条连接上 → 查出来是 0（真机实测：新建任务报「任务创建失败」，
   * 就是这里拿到的 id 是 0，后面 getTask(0) 查不到行）。
   * 所以这里先试 last_insert_rowid，拿不到就退回 `MAX(id)`——
   * 本机库所有表的主键都是 `INTEGER PRIMARY KEY AUTOINCREMENT`，id 单调递增，
   * 刚插完的这一行就是最大值（单机单用户，不存在并发插入）。
   */
  static async insert(sql: string, args: Array<relationalStore.ValueType>, table: string): Promise<number> {
    await Db.exec(sql, args);
    let id: number = 0;
    const rs = await Db.query('SELECT last_insert_rowid() AS id');
    try {
      if (rs.goToFirstRow()) {
        id = rs.getLong(0);
      }
    } catch (e) {
      id = 0;
    }
    Db.close(rs);
    if (id <= 0 && table.length > 0) {
      const rs2 = await Db.query(`SELECT MAX(id) AS id FROM ${table}`);
      try {
        if (rs2.goToFirstRow()) {
          id = rs2.getLong(0);
        }
      } catch (e) {
        id = 0;
      }
      Db.close(rs2);
    }
    hilog.debug(DOMAIN, 'workbench', 'insert into %{public}s -> id=%{public}d', table, id);
    return id;
  }

  /**
   * 安全遍历结果集：逐行回调。ResultSet 的读方法都可能抛异常，
   * 这里统一收口（读不动就当没有更多行），调用方不必每处都写 try/catch。
   */
  static async each(rs: relationalStore.ResultSet, fn: (index: number) => void): Promise<void> {
    try {
      let i: number = 0;
      if (rs.goToFirstRow()) {
        do {
          fn(i);
          i += 1;
        } while (rs.goToNextRow());
      }
    } catch (e) {
      // 读到一半出错就停下，剩余行当作没有
    }
  }

  /** 只读第一行（没有就什么都不做） */
  static async first(rs: relationalStore.ResultSet, fn: () => void): Promise<void> {
    try {
      if (rs.goToFirstRow()) { fn(); }
    } catch (e) {
    }
  }

  /** 关闭结果集（close 也可能抛，包一层） */
  static close(rs: relationalStore.ResultSet): void {
    try {
      rs.close();
    } catch (e) {
    }
  }

  // ── 取值小工具（列名 → 值；列不存在、为 NULL 或读失败时给默认值）──
  static s(rs: relationalStore.ResultSet, col: string): string {
    try {
      const i = rs.getColumnIndex(col);
      if (i < 0 || rs.isColumnNull(i)) { return ''; }
      return rs.getString(i);
    } catch (e) {
      return '';
    }
  }

  static ns(rs: relationalStore.ResultSet, col: string): string | null {
    try {
      const i = rs.getColumnIndex(col);
      if (i < 0 || rs.isColumnNull(i)) { return null; }
      return rs.getString(i);
    } catch (e) {
      return null;
    }
  }

  static n(rs: relationalStore.ResultSet, col: string): number {
    try {
      const i = rs.getColumnIndex(col);
      if (i < 0 || rs.isColumnNull(i)) { return 0; }
      return rs.getLong(i);
    } catch (e) {
      return 0;
    }
  }

  static nn(rs: relationalStore.ResultSet, col: string): number | null {
    try {
      const i = rs.getColumnIndex(col);
      if (i < 0 || rs.isColumnNull(i)) { return null; }
      return rs.getLong(i);
    } catch (e) {
      return null;
    }
  }

  /** 本地墙上时间 yyyy-MM-ddTHH:mm（不用 toISOString，会差 8 小时） */
  static now(): string {
    const d = new Date();
    const p = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  /** 今天 yyyy-MM-dd */
  static today(): string {
    return Db.now().substring(0, 10);
  }

  /** 读一个设置项 */
  static async getSetting(key: string, fallback: string): Promise<string> {
    const rs = await Db.query('SELECT value FROM setting WHERE key = ?', [key]);
    let v: string = fallback;
    try {
      if (rs.goToFirstRow()) { v = rs.getString(0); }
    } catch (e) {
      v = fallback;
    }
    Db.close(rs);
    return v;
  }

  /** 写一个设置项 */
  static async setSetting(key: string, value: string): Promise<void> {
    await Db.exec('INSERT OR REPLACE INTO setting (key, value) VALUES (?,?)', [key, value]);
  }

  /** 表里有没有数据（用来判断是不是首次启动） */
  static async countRows(table: string): Promise<number> {
    const rs = await Db.query(`SELECT COUNT(*) AS n FROM ${table}`);
    let n: number = 0;
    try {
      if (rs.goToFirstRow()) { n = rs.getLong(0); }
    } catch (e) {
      n = 0;
    }
    Db.close(rs);
    return n;
  }
}
