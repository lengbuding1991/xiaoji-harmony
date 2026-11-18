// entry/src/main/ets/db/Db.ets
// 本地数据库：HarmonyOS RDB（@ohos.data.relationalStore）。
// v4.0 起 App 完全离线 —— 所有数据存在手机本地的 workbench.db，不连任何服务器。
// 表结构与「个人工作台」lib/db.ts 的 SCHEMA 一一对应，方便导出 / 导入 / 将来同步。
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const DB_NAME = 'workbench.db';

/** 一列的定义（从建表语句 DDL 里解析出来的） */
interface ColumnDef {
  name: string;
  type: string;
  notNull: boolean;
  def: string;   // DEFAULT 后面的原始文本（含引号），没有就是空串
}

/** 一张表的定义 */
interface TableSchema {
  table: string;
  columns: ColumnDef[];
}

export class Db {
  /**
   * 库结构版本。
   *
   * v4.28 起引入：App 升级是覆盖安装，但 /data/app/el2/.../database/workbench.db
   * 这个文件是**保留**的 —— 老用户升级上来，拿到的是旧结构 + 旧数据。
   * 所以「加字段 / 改表」必须先迁移再让新代码去用，否则新代码读旧库会少列、
   * 写新列直接报错（表现是「升级完某个功能一点就崩」）。
   *
   * 规则：
   *   - **加字段不用管**：只要把新字段写进下面的 DDL，开库时会自动补到老库上
   *     （见 syncColumns()，老库一行数据都不动，只多一列）；
   *   - 遇到「改类型 / 改列名 / 删列 / 数据回填」这类不是纯加列的变更，
   *     才需要在这里 +1，并在 migrate() 里补一段 `if (from < N) { ... }`；
   *   - 迁移里只允许做「加列 / 加索引 / 回填默认值」这类幂等操作，
   *     **绝不允许删表删数据**。
   *
   * 1 = v4.28 之前的基线结构（10 张表 + 6 索引），老库升上来会被打上这个版本号。
   */
  static readonly DB_VERSION: number = 1;

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
      color TEXT NOT NULL DEFAULT '#523593',
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
        securityLevel: relationalStore.SecurityLevel.S2,
        // v4.28：库文件损坏时**不要**自动删库重建。
        // 默认是 false，但显式写出来 —— 这一条是「用户数据不许被覆盖」的底线，
        // 将来谁改了它，就等于允许平台在异常时清空用户的库。
        allowRebuild: false
      };
      Db.store = await relationalStore.getRdbStore(ctx, config);
      for (let i = 0; i < Db.DDL.length; i++) {
        await Db.store.executeSql(Db.DDL[i]);
      }
      // v4.28：先把「DDL 里声明、老库里还没有」的列补上（只加列，不动数据），
      // 这样以后只要往 DDL 里加一行字段，老用户升级上来自动就有这一列，
      // 不会出现「读得到但写不进去」。
      await Db.syncColumns(Db.parseSchema(Db.DDL));
      await Db.migrate();
      Db.opened = true;
      hilog.debug(DOMAIN, 'workbench', 'local db ready: %{public}s v%{public}d',
        DB_NAME, Db.store.version);
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, 'workbench', 'open db failed: %{public}s', err.message ?? 'unknown');
      throw err;
    }
  }

  /**
   * 结构迁移（v4.28 新增）。
   *
   * 老用户的库 version 是 0（历史上从来没设过），新装的库也是 0。
   * 这里统一往上顶到 DB_VERSION：每一档只做「加列 / 加索引」，
   * 不会 DROP、不会 DELETE，跑多少遍都安全。
   *
   * 新增字段的模板（以后改表结构照这个写）：
   *   if (from < 2) {
   *     await Db.addColumnIfMissing('task', 'some_new_col', 'TEXT');
   *   }
   */
  private static async migrate(): Promise<void> {
    const s: relationalStore.RdbStore = Db.need();
    let from: number = 0;
    try {
      from = s.version;
    } catch (e) {
      from = 0;
    }
    if (from >= Db.DB_VERSION) {
      // 已经是新结构（或更新的结构，说明用户装过更新的版本又降级回来）——
      // 不要动它，也不要为了「对齐」去删列删表。
      return;
    }
    hilog.info(DOMAIN, 'workbench', 'migrate db %{public}d -> %{public}d', from, Db.DB_VERSION);
    if (from < 1) {
      // 1 = 基线。v4.28 之前的库没有版本号，结构也就是 DDL 里那 10 张表 ——
      // 上面已经用 CREATE TABLE IF NOT EXISTS 全建过一遍了，这里不用补任何东西，
      // 只是把版本号打上，让后续迁移有个起点。
    }
    try {
      s.version = Db.DB_VERSION;
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, 'workbench', 'set db version failed: %{public}s', err.message ?? 'unknown');
    }
  }

  /**
   * 加一列（幂等）：列已存在就跳过。
   * 迁移里加字段一律走它，不要直接 ALTER TABLE —— 迁移可能因为断电/杀进程重跑。
   */
  static async addColumnIfMissing(table: string, column: string, type: string): Promise<boolean> {
    const have: string[] = await Db.tableColumns(table);
    if (have.indexOf(column) >= 0) { return false; }
    await Db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);
    hilog.info(DOMAIN, 'workbench', 'added column %{public}s.%{public}s', table, column);
    return true;
  }

  /**
   * 解析建表语句，得出「表 → 列定义」。
   *
   * 这是「声明式加列」的基础：DDL 是唯一的真相来源，
   * 以后要加字段，只要在 DDL 里多写一行，开库时自动补到老库上，
   * **不存在「忘了写迁移」这种事**。
   */
  private static parseSchema(ddl: string[]): TableSchema[] {
    const out: TableSchema[] = [];
    const head: string = 'CREATE TABLE IF NOT EXISTS';
    for (const stmt of ddl) {
      const i: number = stmt.indexOf(head);
      if (i < 0) { continue; }
      const rest: string = stmt.substring(i + head.length).trim();
      const sp: number = rest.indexOf(' ');
      if (sp < 0) { continue; }
      const table: string = rest.substring(0, sp).trim();
      const lb: number = rest.indexOf('(');
      const rb: number = rest.lastIndexOf(')');
      if (lb < 0 || rb <= lb) { continue; }
      const body: string = rest.substring(lb + 1, rb);
      const cols: ColumnDef[] = [];
      // 一列一行，用「逗号 + 换行」切：DEFAULT 值里带逗号也不会被切错
      const parts: string[] = body.split(/,\s*\r?\n/);
      for (const part of parts) {
        const line: string = part.trim().replace(/\s+/g, ' ');
        if (line.length === 0) { continue; }
        const up: string = line.toUpperCase();
        // 表级约束不是列，跳过
        if (up.startsWith('PRIMARY KEY') || up.startsWith('FOREIGN KEY')
          || up.startsWith('UNIQUE') || up.startsWith('CHECK') || up.startsWith('CONSTRAINT')) {
          continue;
        }
        const sp2: number = line.indexOf(' ');
        if (sp2 < 0) { continue; }
        const name: string = line.substring(0, sp2).trim();
        const tail: string = line.substring(sp2 + 1).trim();
        const tp: number = tail.indexOf(' ');
        const type: string = (tp < 0 ? tail : tail.substring(0, tp)).toUpperCase();
        const more: string = (tp < 0 ? '' : tail.substring(tp + 1)).trim();
        // 内联主键列不能靠 ALTER TABLE ADD COLUMN 加（SQLite 不允许），跳过
        if (more.toUpperCase().indexOf('PRIMARY KEY') >= 0) { continue; }
        const notNull: boolean = more.toUpperCase().indexOf('NOT NULL') >= 0;
        let def: string = '';
        const di: number = more.toUpperCase().indexOf('DEFAULT ');
        if (di >= 0) {
          def = more.substring(di + 8).trim();
          const spd: number = def.indexOf(' ');
          if (spd >= 0) { def = def.substring(0, spd); }
        }
        cols.push({ name: name, type: type, notNull: notNull, def: def });
      }
      out.push({ table: table, columns: cols });
    }
    return out;
  }

  /**
   * 把「DDL 里声明、但老库里还没有」的列补上。
   *
   * 规则：**只加列，绝不删列、绝不改已有列**。
   * 加出来的列，老数据那一行的值是这一列的默认值（或者 NULL），
   * 原来那些行**一个字都不会变**。
   *
   * 注意：这里必须直接用 Db.store，不能用 Db.exec / Db.query ——
   * 那两个会走 ensure() 去 await Db.opening，而此刻我们正在 Db.opening 里面，
   * 会把自己等死（死锁）。
   */
  private static async syncColumns(schema: TableSchema[]): Promise<void> {
    const s: relationalStore.RdbStore = Db.need();
    for (const t of schema) {
      const have: string[] = await Db.columnsOf(s, t.table);
      if (have.length === 0) { continue; }  // 表读不到（不该发生），跳过
      for (const c of t.columns) {
        if (have.indexOf(c.name) >= 0) { continue; }
        try {
          await s.executeSql(`ALTER TABLE ${t.table} ADD COLUMN ${Db.altColumnDef(c)}`);
          hilog.info(DOMAIN, 'workbench', 'schema sync: added %{public}s.%{public}s',
            t.table, c.name);
        } catch (e) {
          const err = e as Error;
          hilog.error(DOMAIN, 'workbench',
            'schema sync failed on %{public}s.%{public}s: %{public}s',
            t.table, c.name, err.message ?? 'unknown');
        }
      }
    }
  }

  /** ALTER TABLE ADD COLUMN 用的列定义（NOT NULL 必须带默认值，否则 SQLite 会拒绝） */
  private static altColumnDef(c: ColumnDef): string {
    let s: string = `${c.name} ${c.type}`;
    if (c.notNull) {
      let dv: string = c.def;
      if (dv.length === 0) {
        dv = (c.type === 'INTEGER' || c.type === 'REAL') ? '0' : "''";
      }
      s += ` NOT NULL DEFAULT ${dv}`;
    } else if (c.def.length > 0) {
      s += ` DEFAULT ${c.def}`;
    }
    return s;
  }

  /** 读一张表实际有哪些列（一次查询拿到全部列名） */
  private static async columnsOf(s: relationalStore.RdbStore, table: string): Promise<string[]> {
    const names: string[] = [];
    try {
      const rs: relationalStore.ResultSet = await s.querySql(`SELECT * FROM ${table} LIMIT 0`);
      try {
        const arr: string[] = rs.getColumnNames();
        for (const n of arr) { names.push(n); }
      } finally {
        Db.close(rs);
      }
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, 'workbench', 'read columns of %{public}s failed: %{public}s',
        table, err.message ?? 'unknown');
    }
    return names;
  }

  /** 读一张表实际有哪些列（对外版） */
  static async tableColumns(table: string): Promise<string[]> {
    const s: relationalStore.RdbStore = Db.need();
    return Db.columnsOf(s, table);
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
