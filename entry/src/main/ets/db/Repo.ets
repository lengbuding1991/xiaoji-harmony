// entry/src/main/ets/db/Repo.ets
// 本地数据仓库：把原来「打服务端接口」的那一层全部搬到手机本地数据库。
// 对外方法名和返回结构跟原来 HTTP 接口保持一致，视图层几乎不用改。
// 离线优先：任何一步失败都抛异常（跟原来 Http 一样），上层自己 try/catch。
import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { D } from '../utils/DateUtil';
import {
  Task, TaskStatus, Priority, Area, RepeatRule, EventItem, Note, Project, Review,
  Habit, HabitView, ReminderItem, NoteLink, NoteLinksResp, TaskNoteLink, TaskNoteLinksResp,
  SearchHit, SearchTaskHit, SearchNoteHit, SearchResp, TaskCreateResp, TaskPatchResp,
  EventCreateResp, EventPatchResp, NoteCreateResp, NotePatchResp,
  ProjectCreateResp, ProjectPatchResp, HabitsResp, HabitCreateResp,
  HabitLogResp, RemindersResp, OkResp, SettingsResp, TaskCreate, TaskUpdate, EventCreate,
  EventUpdate, NoteCreate, NoteUpdate, ProjectCreate, ProjectUpdate, ReviewSave, HabitCreate,
  HabitUpdate, SettingsPatch, TaskEventLink
} from '../api/Types';

/** 习惯记录回看一年（工作台 lib/habits.ts 是 60 天；我们要算「历史最长连续」+ 补更早的打卡） */
const LOOKBACK: number = 365;

/** 复刻工作台 lib/repeat.ts 的 advance：把日期往后推一格 */
function advance(base: Date, rule: string): Date {
  const n = new Date(base.getTime());
  switch (rule) {
    case 'daily':
      n.setDate(n.getDate() + 1);
      break;
    case 'weekdays':
      do { n.setDate(n.getDate() + 1); } while (n.getDay() === 0 || n.getDay() === 6);
      break;
    case 'weekly':
      n.setDate(n.getDate() + 7);
      break;
    case 'monthly':
      n.setMonth(n.getMonth() + 1);
      break;
    default:
      break;
  }
  return n;
}

/**
 * 把日期往后推一格 —— 日历展开重复日程要用
 * （跟 lib/repeat.ts 同一套规则：daily / weekdays / weekly / monthly）
 */
export function advanceDate(base: Date, rule: string): Date {
  return advance(base, rule);
}

/** 本地墙上时间字符串 yyyy-MM-ddTHH:mm */
function nowStr(): string {
  return Db.now();
}

export class Repo {
  // ───────────────────────── 任务 ─────────────────────────

  static async tasks(): Promise<Task[]> {
    const rs = await Db.query(
      `SELECT * FROM task
       ORDER BY CASE status WHEN 'doing' THEN 0 WHEN 'todo' THEN 1 ELSE 2 END, sort, id DESC`
    );
    const out: Task[] = [];
    await Db.each(rs, () => {
          out.push(Repo.readTask(rs));
    });
    Db.close(rs);
    return out;
  }

  static readTask(rs: relationalStore.ResultSet): Task {
    const t: Task = {
      id: Db.n(rs, 'id'),
      title: Db.s(rs, 'title'),
      note: Db.s(rs, 'note'),
      status: Db.s(rs, 'status') as TaskStatus,
      priority: Db.s(rs, 'priority') as Priority,
      area: Db.s(rs, 'area') as Area,
      project_id: Db.nn(rs, 'project_id'),
      due_date: Db.ns(rs, 'due_date'),
      scheduled_start: Db.ns(rs, 'scheduled_start'),
      scheduled_end: Db.ns(rs, 'scheduled_end'),
      estimate_min: Db.nn(rs, 'estimate_min'),
      done_at: Db.ns(rs, 'done_at'),
      sort: Db.n(rs, 'sort'),
      created_at: Db.s(rs, 'created_at'),
      updated_at: Db.s(rs, 'updated_at'),
      project: Db.s(rs, 'project'),
      tags: Db.s(rs, 'tags'),
      repeat_rule: Db.s(rs, 'repeat_rule') as RepeatRule,
      remind_min: Db.nn(rs, 'remind_min')
    };
    return t;
  }

  static async getTask(id: number): Promise<Task | null> {
    const rs = await Db.query('SELECT * FROM task WHERE id = ?', [id]);
    let t: Task | null = null;
    await Db.first(rs, () => { t = Repo.readTask(rs); });
    Db.close(rs);
    return t;
  }

  static async createTask(body: TaskCreate): Promise<TaskCreateResp> {
    const title: string = (body.title ?? '').trim();
    if (title.length === 0) { throw new Error('任务名不能为空'); }
    const now = nowStr();
    const status: TaskStatus = body.status ?? 'todo';
    const id: number = await Db.insert(
      `INSERT INTO task (title,note,status,priority,area,due_date,scheduled_start,scheduled_end,
        estimate_min,project,project_id,tags,repeat_rule,remind_min,done_at,sort,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        title,
        body.note ?? '',
        status,
        body.priority ?? 'med',
        body.area ?? 'work',
        body.due_date ?? null,
        body.scheduled_start ?? null,
        body.scheduled_end ?? null,
        body.estimate_min ?? null,
        body.project ?? '',
        body.project_id ?? null,
        body.tags ?? '',
        body.repeat_rule ?? 'none',
        body.remind_min ?? null,
        status === 'done' ? now : null,
        0,
        now,
        now
      ],
    'task');
    const task = await Repo.getTask(id);
    if (task === null) { throw new Error('任务创建失败'); }
    const resp: TaskCreateResp = { id: id, task: task };
    return resp;
  }

  static async patchTask(id: number, body: TaskUpdate): Promise<TaskPatchResp> {
    const before = await Repo.getTask(id);
    if (before === null) { throw new Error('任务不存在'); }

    const sets: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    if (body.title !== undefined) { sets.push('title = ?'); args.push(body.title); }
    if (body.note !== undefined) { sets.push('note = ?'); args.push(body.note); }
    if (body.priority !== undefined) { sets.push('priority = ?'); args.push(body.priority); }
    if (body.area !== undefined) { sets.push('area = ?'); args.push(body.area); }
    if (body.due_date !== undefined) { sets.push('due_date = ?'); args.push(body.due_date); }
    if (body.scheduled_start !== undefined) { sets.push('scheduled_start = ?'); args.push(body.scheduled_start); }
    if (body.scheduled_end !== undefined) { sets.push('scheduled_end = ?'); args.push(body.scheduled_end); }
    if (body.estimate_min !== undefined) { sets.push('estimate_min = ?'); args.push(body.estimate_min); }
    if (body.project !== undefined) { sets.push('project = ?'); args.push(body.project); }
    if (body.project_id !== undefined) { sets.push('project_id = ?'); args.push(body.project_id); }
    if (body.tags !== undefined) { sets.push('tags = ?'); args.push(body.tags); }
    if (body.sort !== undefined) { sets.push('sort = ?'); args.push(body.sort); }
    if (body.repeat_rule !== undefined) { sets.push('repeat_rule = ?'); args.push(body.repeat_rule); }
    if (body.remind_min !== undefined) { sets.push('remind_min = ?'); args.push(body.remind_min); }
    if (body.status !== undefined) {
      sets.push('status = ?'); args.push(body.status);
      sets.push('done_at = ?'); args.push(body.status === 'done' ? nowStr() : null);
    }
    if (sets.length > 0) {
      sets.push('updated_at = ?');
      args.push(nowStr());
      args.push(id);
      await Db.exec(`UPDATE task SET ${sets.join(', ')} WHERE id = ?`, args);
    }
    const task = await Repo.getTask(id);
    if (task === null) { throw new Error('任务不存在'); }

    // 重复任务：勾完这一条就把下一次排出来（工作台 tasks/[id]/route.ts 的做法）
    let next: Task | null = null;
    const becameDone: boolean = body.status === 'done' && before.status !== 'done';
    if (becameDone && task.repeat_rule !== 'none') {
      const anchor: string = (task.due_date ?? task.scheduled_start ?? '').substring(0, 10);
      if (anchor.length > 0) {
        const base = D.parse(anchor);
        const nextDate = advance(base, task.repeat_rule);
        const nd: string = D.key(nextDate);
        const shift: number = nextDate.getTime() - base.getTime();
        let nStart: string | null = null;
        let nEnd: string | null = null;
        if (task.scheduled_start !== null && task.scheduled_start.length > 0) {
          nStart = Repo.shiftTime(task.scheduled_start, shift);
        }
        if (task.scheduled_end !== null && task.scheduled_end.length > 0) {
          nEnd = Repo.shiftTime(task.scheduled_end, shift);
        }
        const nid: number = await Db.insert(
          `INSERT INTO task (title,note,status,priority,area,due_date,scheduled_start,scheduled_end,
            estimate_min,project,project_id,tags,repeat_rule,remind_min,done_at,sort,created_at,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL,?,?,?)`,
          [
            task.title, task.note, 'todo', task.priority, task.area, nd, nStart, nEnd,
            task.estimate_min, task.project, task.project_id, task.tags, task.repeat_rule,
            task.remind_min, task.sort, nowStr(), nowStr()
          ],
        'task');
        next = await Repo.getTask(nid);
      }
    }
    const resp: TaskPatchResp = { task: task, next: next };
    return resp;
  }

  /** 时间戳往后推 shift 毫秒，保持 yyyy-MM-ddTHH:mm 格式 */
  private static shiftTime(at: string, shift: number): string {
    const d = new Date(D.parse(at).getTime() + shift);
    const p = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  static async deleteTask(id: number): Promise<OkResp> {
    await Db.exec('DELETE FROM task WHERE id = ?', [id]);
    await Db.exec('DELETE FROM note_task WHERE task_id = ?', [id]);
    await Db.exec('DELETE FROM task_event WHERE task_id = ?', [id]);
    const r: OkResp = { ok: true };
    return r;
  }

  // ───────────────────────── 日程 ─────────────────────────

  static async events(): Promise<EventItem[]> {
    const rs = await Db.query('SELECT * FROM event ORDER BY start_at ASC, id ASC');
    const out: EventItem[] = [];
    await Db.each(rs, () => {
          out.push(Repo.readEvent(rs));
    });
    Db.close(rs);
    return out;
  }

  static readEvent(rs: relationalStore.ResultSet): EventItem {
    const e: EventItem = {
      id: Db.n(rs, 'id'),
      title: Db.s(rs, 'title'),
      start_at: Db.s(rs, 'start_at'),
      end_at: Db.ns(rs, 'end_at'),
      all_day: Db.n(rs, 'all_day'),
      location: Db.s(rs, 'location'),
      note: Db.s(rs, 'note'),
      created_at: Db.s(rs, 'created_at'),
      repeat_rule: Db.s(rs, 'repeat_rule') as RepeatRule,
      remind_min: Db.nn(rs, 'remind_min')
    };
    return e;
  }

  static async getEvent(id: number): Promise<EventItem | null> {
    const rs = await Db.query('SELECT * FROM event WHERE id = ?', [id]);
    let e: EventItem | null = null;
    await Db.first(rs, () => { e = Repo.readEvent(rs); });
    Db.close(rs);
    return e;
  }

  static async createEvent(body: EventCreate): Promise<EventCreateResp> {
    const title: string = (body.title ?? '').trim();
    if (title.length === 0) { throw new Error('日程名不能为空'); }
    const id: number = await Db.insert(
      `INSERT INTO event (title,start_at,end_at,all_day,location,note,created_at,repeat_rule,remind_min)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      [
        title,
        body.start_at ?? nowStr(),
        body.end_at ?? null,
        body.all_day ?? 0,
        body.location ?? '',
        body.note ?? '',
        nowStr(),
        body.repeat_rule ?? 'none',
        body.remind_min ?? null
      ],
    'event');
    const event = await Repo.getEvent(id);
    if (event === null) { throw new Error('日程创建失败'); }
    const resp: EventCreateResp = { event: event };
    return resp;
  }

  static async patchEvent(id: number, body: EventUpdate): Promise<EventPatchResp> {
    const before = await Repo.getEvent(id);
    if (before === null) { throw new Error('日程不存在'); }
    const sets: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    if (body.title !== undefined) { sets.push('title = ?'); args.push(body.title); }
    if (body.start_at !== undefined) { sets.push('start_at = ?'); args.push(body.start_at); }
    if (body.end_at !== undefined) { sets.push('end_at = ?'); args.push(body.end_at); }
    if (body.all_day !== undefined) { sets.push('all_day = ?'); args.push(body.all_day); }
    if (body.location !== undefined) { sets.push('location = ?'); args.push(body.location); }
    if (body.note !== undefined) { sets.push('note = ?'); args.push(body.note); }
    if (body.repeat_rule !== undefined) { sets.push('repeat_rule = ?'); args.push(body.repeat_rule); }
    if (body.remind_min !== undefined) { sets.push('remind_min = ?'); args.push(body.remind_min); }
    if (sets.length > 0) {
      args.push(id);
      await Db.exec(`UPDATE event SET ${sets.join(', ')} WHERE id = ?`, args);
    }
    const event = await Repo.getEvent(id);
    if (event === null) { throw new Error('日程不存在'); }
    const resp: EventPatchResp = { event: event };
    return resp;
  }

  static async deleteEvent(id: number): Promise<OkResp> {
    await Db.exec('DELETE FROM event WHERE id = ?', [id]);
    await Db.exec('DELETE FROM task_event WHERE event_id = ?', [id]);
    const r: OkResp = { ok: true };
    return r;
  }

  // ───────────────────────── 灵感 ─────────────────────────

  static async notes(includeArchived: boolean = false): Promise<Note[]> {
    const sql: string = includeArchived
      ? 'SELECT * FROM note ORDER BY pinned DESC, updated_at DESC, id DESC'
      : 'SELECT * FROM note WHERE archived = 0 ORDER BY pinned DESC, updated_at DESC, id DESC';
    const rs = await Db.query(sql);
    const out: Note[] = [];
    await Db.each(rs, () => {
          out.push(Repo.readNote(rs));
    });
    Db.close(rs);
    return out;
  }

  static readNote(rs: relationalStore.ResultSet): Note {
    const n: Note = {
      id: Db.n(rs, 'id'),
      title: Db.s(rs, 'title'),
      content: Db.s(rs, 'content'),
      source: Db.s(rs, 'source'),
      pinned: Db.n(rs, 'pinned'),
      created_at: Db.s(rs, 'created_at'),
      updated_at: Db.s(rs, 'updated_at'),
      tags: Db.s(rs, 'tags'),
      archived: Db.n(rs, 'archived'),
      project_id: Db.nn(rs, 'project_id')
    };
    return n;
  }

  static async getNote(id: number): Promise<Note | null> {
    const rs = await Db.query('SELECT * FROM note WHERE id = ?', [id]);
    let n: Note | null = null;
    await Db.first(rs, () => { n = Repo.readNote(rs); });
    Db.close(rs);
    return n;
  }

  static async createNote(body: NoteCreate): Promise<NoteCreateResp> {
    const now = nowStr();
    const id: number = await Db.insert(
      `INSERT INTO note (title,content,source,tags,archived,pinned,project_id,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      [
        body.title ?? '',
        body.content ?? '',
        body.source ?? '灵感',
        '',
        0,
        0,
        null,
        now,
        now
      ],
    'note');
    const note = await Repo.getNote(id);
    if (note === null) { throw new Error('记录创建失败'); }
    const resp: NoteCreateResp = { note: note };
    return resp;
  }

  static async patchNote(id: number, body: NoteUpdate): Promise<NotePatchResp> {
    const before = await Repo.getNote(id);
    if (before === null) { throw new Error('记录不存在'); }
    const sets: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    if (body.title !== undefined) { sets.push('title = ?'); args.push(body.title); }
    if (body.content !== undefined) { sets.push('content = ?'); args.push(body.content); }
    if (body.source !== undefined) { sets.push('source = ?'); args.push(body.source); }
    if (body.pinned !== undefined) { sets.push('pinned = ?'); args.push(body.pinned); }
    if (body.archived !== undefined) { sets.push('archived = ?'); args.push(body.archived); }
    if (body.tags !== undefined) { sets.push('tags = ?'); args.push(body.tags); }
    if (body.project_id !== undefined) { sets.push('project_id = ?'); args.push(body.project_id); }
    if (sets.length > 0) {
      sets.push('updated_at = ?');
      args.push(nowStr());
      args.push(id);
      await Db.exec(`UPDATE note SET ${sets.join(', ')} WHERE id = ?`, args);
    }
    const note = await Repo.getNote(id);
    if (note === null) { throw new Error('记录不存在'); }
    const resp: NotePatchResp = { note: note };
    return resp;
  }

  static async deleteNote(id: number): Promise<OkResp> {
    await Db.exec('DELETE FROM note WHERE id = ?', [id]);
    await Db.exec('DELETE FROM note_task WHERE note_id = ?', [id]);
    const r: OkResp = { ok: true };
    return r;
  }

  // ───────────────────────── 项目 ─────────────────────────

  static async projects(): Promise<Project[]> {
    const rs = await Db.query(
      `SELECT p.*,
        (SELECT COUNT(*) FROM task t WHERE t.project_id = p.id) AS total,
        (SELECT COUNT(*) FROM task t WHERE t.project_id = p.id AND t.status = 'done') AS done
       FROM project p ORDER BY p.sort ASC, p.id ASC`
    );
    const out: Project[] = [];
    await Db.each(rs, () => {
          const p: Project = {
            id: Db.n(rs, 'id'),
            name: Db.s(rs, 'name'),
            color: Db.s(rs, 'color'),
            area: Db.s(rs, 'area') as Area,
            status: Db.s(rs, 'status'),
            note: Db.s(rs, 'note'),
            sort: Db.n(rs, 'sort'),
            created_at: Db.s(rs, 'created_at'),
            target_date: Db.ns(rs, 'target_date'),
            total: Db.n(rs, 'total'),
            done: Db.n(rs, 'done')
          };
          out.push(p);
    });
    Db.close(rs);
    return out;
  }

  static async createProject(body: ProjectCreate): Promise<ProjectCreateResp> {
    const name: string = (body.name ?? '').trim();
    if (name.length === 0) { throw new Error('项目名不能为空'); }
    const id: number = await Db.insert(
      `INSERT INTO project (name,color,area,status,note,sort,target_date,created_at)
       VALUES (?,?,?,?,?,?,?,?)`,
      [
        name,
        body.color ?? '#A78BFA',
        body.area ?? 'work',
        'active',
        body.note ?? '',
        0,
        body.target_date ?? null,
        nowStr()
      ],
    'project');
    const all = await Repo.projects();
    for (const p of all) {
      if (p.id === id) {
        const resp: ProjectCreateResp = { project: p };
        return resp;
      }
    }
    throw new Error('项目创建失败');
  }

  static async patchProject(id: number, body: ProjectUpdate): Promise<ProjectPatchResp> {
    const sets: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    if (body.name !== undefined) { sets.push('name = ?'); args.push(body.name); }
    if (body.color !== undefined) { sets.push('color = ?'); args.push(body.color); }
    if (body.area !== undefined) { sets.push('area = ?'); args.push(body.area); }
    if (body.status !== undefined) { sets.push('status = ?'); args.push(body.status); }
    if (body.note !== undefined) { sets.push('note = ?'); args.push(body.note); }
    if (body.sort !== undefined) { sets.push('sort = ?'); args.push(body.sort); }
    if (body.target_date !== undefined) { sets.push('target_date = ?'); args.push(body.target_date); }
    if (sets.length > 0) {
      args.push(id);
      await Db.exec(`UPDATE project SET ${sets.join(', ')} WHERE id = ?`, args);
    }
    const all = await Repo.projects();
    for (const p of all) {
      if (p.id === id) {
        const resp: ProjectPatchResp = { project: p };
        return resp;
      }
    }
    throw new Error('项目不存在');
  }

  static async deleteProject(id: number): Promise<OkResp> {
    await Db.exec('DELETE FROM project WHERE id = ?', [id]);
    await Db.exec('UPDATE task SET project_id = NULL WHERE project_id = ?', [id]);
    const r: OkResp = { ok: true };
    return r;
  }

  // ───────────────────────── 复盘 ─────────────────────────

  static async reviews(): Promise<Review[]> {
    const rs = await Db.query('SELECT * FROM review ORDER BY date DESC, id DESC');
    const out: Review[] = [];
    await Db.each(rs, () => {
          const r: Review = {
            id: Db.n(rs, 'id'),
            date: Db.s(rs, 'date'),
            type: Db.s(rs, 'type') as 'daily' | 'weekly',
            did: Db.s(rs, 'did'),
            stuck: Db.s(rs, 'stuck'),
            tomorrow: Db.s(rs, 'tomorrow'),
            summary: Db.s(rs, 'summary'),
            ai_generated: Db.n(rs, 'ai_generated'),
            created_at: Db.s(rs, 'created_at'),
            updated_at: Db.s(rs, 'updated_at')
          };
          out.push(r);
    });
    Db.close(rs);
    return out;
  }

  /** 同一天同一类型只有一篇：有就更新，没有就插入 */
  static async saveReview(body: ReviewSave): Promise<OkResp> {
    const date: string = body.date ?? D.today();
    const type: string = body.type ?? 'daily';
    const now = nowStr();
    const rs = await Db.query('SELECT id FROM review WHERE date = ? AND type = ?', [date, type]);
    let exists: boolean = false;
    await Db.first(rs, () => { exists = true; });
    Db.close(rs);
    if (exists) {
      await Db.exec(
        `UPDATE review SET did = ?, stuck = ?, tomorrow = ?, summary = ?, updated_at = ?
         WHERE date = ? AND type = ?`,
        [body.did ?? '', body.stuck ?? '', body.tomorrow ?? '', body.summary ?? '', now, date, type]
      );
    } else {
      await Db.exec(
        `INSERT INTO review (date,type,did,stuck,tomorrow,summary,ai_generated,created_at,updated_at)
         VALUES (?,?,?,?,?,?,0,?,?)`,
        [date, type, body.did ?? '', body.stuck ?? '', body.tomorrow ?? '', body.summary ?? '', now, now]
      );
    }
    const r: OkResp = { ok: true };
    return r;
  }

  static async deleteReview(id: number): Promise<OkResp> {
    await Db.exec('DELETE FROM review WHERE id = ?', [id]);
    const r: OkResp = { ok: true };
    return r;
  }

  // ───────────────────────── 习惯 ─────────────────────────

  /**
   * 本周（周一 ~ 周日）的 7 个日期。
   * v4.4：以前「打卡圆点」画的是周一~周日，「本周 N/7」算的却是滚动 7 天
   * ⇒ 会出现「本周 3/7 但只有 1 个点亮」。两个窗口必须是同一个。
   */
  static calendarWeek(): string[] {
    const out: string[] = [];
    const start: Date = D.parse(`${D.weekStart()}T00:00`);
    for (let i = 0; i < 7; i++) {
      out.push(D.key(D.dateAdd(start, i)));
    }
    return out;
  }

  static async habits(): Promise<HabitsResp> {
    const today: string = Db.today();
    const days: string[] = D.lastDays(LOOKBACK);
    // v4.13：圆点窗口从「自然周（周一~周日）」改成「最近 7 天」滚动 ——
    // 否则周一补不了昨天（昨天属于上一周），补卡在最需要的那天失效。
    const week: string[] = D.lastDays(7);

    const rs = await Db.query('SELECT * FROM habit WHERE archived = 0 ORDER BY sort ASC, id ASC');
    const list: Habit[] = [];
    await Db.each(rs, () => {
          const h: Habit = {
            id: Db.n(rs, 'id'),
            name: Db.s(rs, 'name'),
            color: Db.s(rs, 'color'),
            sort: Db.n(rs, 'sort'),
            archived: Db.n(rs, 'archived'),
            created_at: Db.s(rs, 'created_at')
          };
          list.push(h);
    });
    Db.close(rs);

    // 一次查齐打卡记录
    const lrs = await Db.query('SELECT habit_id, date FROM habit_log WHERE date >= ? ORDER BY date', [days[0]]);
    const map = new Map<number, string[]>();
    await Db.each(lrs, () => {
          const hid: number = lrs.getLong(0);
          const d: string = lrs.getString(1);
          const arr: string[] | undefined = map.get(hid);
          if (arr === undefined) { map.set(hid, [d]); } else { arr.push(d); }
    });
    Db.close(lrs);

    const views: HabitView[] = [];
    for (const h of list) {
      const logs: string[] = map.get(h.id) ?? [];
      const v: HabitView = {
        id: h.id,
        name: h.name,
        color: h.color,
        sort: h.sort,
        archived: h.archived,
        created_at: h.created_at,
        logs: logs,
        streak: Repo.streak(logs, today),
        bestStreak: Repo.bestStreak(logs),
        doneToday: logs.indexOf(today) >= 0,
        weekDone: Repo.countIn(week, logs)
      };
      views.push(v);
    }
    const resp: HabitsResp = { today: today, days: week, habits: views };
    return resp;
  }

  /** 连续天数：今天没打卡就从昨天往前数（免得零点一过就归零） */
  private static streak(logs: string[], today: string): number {
    let cursor: string = logs.indexOf(today) >= 0 ? today : D.addDays(today, -1);
    let n: number = 0;
    while (logs.indexOf(cursor) >= 0) {
      n += 1;
      cursor = D.addDays(cursor, -1);
    }
    return n;
  }

  /** 历史最长连续天数（成就，不会归零） */
  private static bestStreak(logs: string[]): number {
    if (logs.length === 0) {
      return 0;
    }
    const sorted: string[] = logs.slice().sort();
    let best: number = 1;
    let cur: number = 1;
    for (let i = 1; i < sorted.length; i++) {
      if (D.addDays(sorted[i - 1], 1) === sorted[i]) {
        cur += 1;
        if (cur > best) { best = cur; }
      } else {
        cur = 1;
      }
    }
    return best;
  }

  private static countIn(days: string[], logs: string[]): number {
    let n: number = 0;
    for (const d of days) {
      if (logs.indexOf(d) >= 0) { n += 1; }
    }
    return n;
  }

  static async createHabit(body: HabitCreate): Promise<HabitCreateResp> {
    const name: string = (body.name ?? '').trim();
    if (name.length === 0) { throw new Error('习惯名不能为空'); }
    if (name.length > 40) { throw new Error('习惯名最多 40 个字'); }
    const rs = await Db.query('SELECT MAX(sort) AS n FROM habit');
    let maxSort: number = 0;
    await Db.first(rs, () => { maxSort = rs.getLong(0); });
    Db.close(rs);
    const id: number = await Db.insert(
      'INSERT INTO habit (name,color,sort,archived,created_at) VALUES (?,?,?,0,?)',
      [name, body.color ?? '#3AC8C2', maxSort + 1, nowStr()],
    'habit');
    const r = await Repo.habits();
    let created: HabitView | null = null;
    for (const h of r.habits) {
      if (h.id === id) { created = h; }
    }
    if (created === null) { throw new Error('习惯创建失败'); }
    const resp: HabitCreateResp = {
      today: r.today, days: r.days, habits: r.habits, habit: created
    };
    return resp;
  }

  static async patchHabit(id: number, body: HabitUpdate): Promise<HabitsResp> {
    const sets: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    if (body.name !== undefined) { sets.push('name = ?'); args.push(body.name); }
    if (body.color !== undefined) { sets.push('color = ?'); args.push(body.color); }
    if (body.sort !== undefined) { sets.push('sort = ?'); args.push(body.sort); }
    if (body.archived !== undefined) { sets.push('archived = ?'); args.push(body.archived); }
    if (sets.length > 0) {
      args.push(id);
      await Db.exec(`UPDATE habit SET ${sets.join(', ')} WHERE id = ?`, args);
    }
    return await Repo.habits();
  }

  static async deleteHabit(id: number): Promise<HabitsResp> {
    await Db.exec('DELETE FROM habit WHERE id = ?', [id]);
    await Db.exec('DELETE FROM habit_log WHERE habit_id = ?', [id]);
    return await Repo.habits();
  }

  /** 打卡 / 取消打卡（同一个接口来回切） */
  static async toggleHabit(habitId: number, date: string): Promise<HabitLogResp> {
    const today: string = Db.today();
    const day: string = date.length > 0 ? date : today;
    if (day > today) { throw new Error('还没到那天，不能提前打卡'); }
    const rs = await Db.query('SELECT id FROM habit_log WHERE habit_id = ? AND date = ?', [habitId, day]);
    let existed: boolean = false;
    await Db.first(rs, () => { existed = true; });
    Db.close(rs);
    if (existed) {
      await Db.exec('DELETE FROM habit_log WHERE habit_id = ? AND date = ?', [habitId, day]);
    } else {
      await Db.exec('INSERT INTO habit_log (habit_id,date,created_at) VALUES (?,?,?)',
        [habitId, day, nowStr()]);
    }
    const r = await Repo.habits();
    const resp: HabitLogResp = {
      today: r.today, days: r.days, habits: r.habits, done: !existed, date: day
    };
    return resp;
  }

  // ───────────────────────── 提醒 ─────────────────────────

  /** 待提醒列表：逾期任务 / 今天到期 / 12 小时内要做 / 到了提醒点的 */
  static async reminders(): Promise<RemindersResp> {
    const nowStrV: string = nowStr();
    const today: string = nowStrV.substring(0, 10);
    const horizon: string = Repo.plusMinutes(nowStrV, 12 * 60);
    const items: ReminderItem[] = [];

    const trs = await Db.query("SELECT * FROM task WHERE status <> 'done'");
    await Db.each(trs, () => {
          const t = Repo.readTask(trs);
          const at: string = (t.scheduled_start ?? t.due_date ?? '').substring(0, 16);
          if (at.length === 0) { return; }
          const hasTime: boolean = at.length > 10;
          const overdue: boolean = hasTime ? (at < nowStrV) : (at < today);
          let remindAt: string | undefined = undefined;
          if (hasTime && t.remind_min !== null) {
            remindAt = Repo.minusMinutes(at, t.remind_min);
          }
          const todayDue: boolean = at.substring(0, 10) === today;
          const within: boolean = hasTime && at >= nowStrV && at <= horizon;
          const remindDue: boolean = remindAt !== undefined && remindAt <= nowStrV;
          if (!overdue && !todayDue && !within && !remindDue) { return; }
          if (!hasTime && !todayDue) { return; }
          const item: ReminderItem = {
            kind: 'task', id: t.id, title: t.title, at: at,
            priority: t.priority, overdue: overdue
          };
          if (remindAt !== undefined) { item.remindAt = remindAt; }
          items.push(item);
    });
    Db.close(trs);

    // 日程：带重复的先展开，否则「每天 9:30 的站会」明天就提醒不到了
    const ers = await Db.query('SELECT * FROM event');
    const events: EventItem[] = [];
    await Db.each(ers, () => {
          events.push(Repo.readEvent(ers));
    });
    Db.close(ers);

    const horizon24: string = Repo.plusMinutes(nowStrV, 24 * 60);
    const seen: number[] = [];
    for (const e of events) {
      const rule: string = e.repeat_rule ?? 'none';
      let start: Date = D.parse(e.start_at);
      let guard: number = 0;
      if (rule !== 'none') {
        while (Repo.fmtDate(start) < nowStrV && guard++ < 400) { start = advance(start, rule); }
      }
      guard = 0;
      while (Repo.fmtDate(start) <= horizon24 && guard++ < 400) {
        const at: string = Repo.fmtDate(start);
        if (at >= nowStrV && at <= horizon && seen.indexOf(e.id) < 0) {
          seen.push(e.id);
          const item: ReminderItem = {
            kind: 'event', id: e.id, title: e.title, at: at, priority: 'med', overdue: false
          };
          if (e.remind_min !== null) {
            item.remindAt = Repo.minusMinutes(at, e.remind_min);
          }
          items.push(item);
        }
        if (rule === 'none') { break; }
        start = advance(start, rule);
      }
    }

    items.sort((a: ReminderItem, b: ReminderItem) => {
      if (a.overdue !== b.overdue) { return a.overdue ? -1 : 1; }
      return a.at < b.at ? -1 : 1;
    });
    const resp: RemindersResp = { items: items.slice(0, 30), now: nowStrV };
    return resp;
  }

  private static fmtDate(d: Date): string {
    const p = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  private static plusMinutes(at: string, minutes: number): string {
    return Repo.fmtDate(new Date(D.parse(at).getTime() + minutes * 60000));
  }

  private static minusMinutes(at: string, minutes: number): string {
    return Repo.fmtDate(new Date(D.parse(at).getTime() - minutes * 60000));
  }

  // ───────────────────────── 设置 ─────────────────────────

  static async settings(): Promise<SettingsResp> {
    const userName: string = await Db.getSetting('user_name', '');
    const r: SettingsResp = {
      user_name: userName,
      ai_base_url: '',
      ai_model: '',
      ai_key_set: false
    };
    return r;
  }

  static async patchSettings(body: SettingsPatch): Promise<OkResp> {
    if (body.user_name !== undefined) {
      await Db.setSetting('user_name', body.user_name);
    }
    const r: OkResp = { ok: true };
    return r;
  }

  // ───────────────────────── 关联（笔记 ↔ 任务）─────────────────────────

  static async noteLinks(noteId: number): Promise<NoteLinksResp> {
    const rs = await Db.query(
      `SELECT l.id AS id, l.created_at AS created_at, l.task_id AS task_id,
        t.title AS title, t.status AS status, t.due_date AS due_date,
        t.priority AS priority, t.area AS area
       FROM note_task l JOIN task t ON t.id = l.task_id
       WHERE l.note_id = ? ORDER BY l.id ASC`,
      [noteId]
    );
    const links: NoteLink[] = [];
    await Db.each(rs, () => {
          const l: NoteLink = {
            id: Db.n(rs, 'id'),
            created_at: Db.s(rs, 'created_at'),
            task_id: Db.n(rs, 'task_id'),
            title: Db.s(rs, 'title'),
            status: Db.s(rs, 'status'),
            due_date: Db.ns(rs, 'due_date'),
            priority: Db.s(rs, 'priority'),
            area: Db.s(rs, 'area')
          };
          links.push(l);
    });
    Db.close(rs);
    const resp: NoteLinksResp = { links: links };
    return resp;
  }

  static async taskLinks(taskId: number): Promise<TaskNoteLinksResp> {
    const rs = await Db.query(
      `SELECT l.id AS id, l.note_id AS note_id, n.title AS title, n.content AS content,
        n.created_at AS created_at, n.updated_at AS updated_at
       FROM note_task l JOIN note n ON n.id = l.note_id
       WHERE l.task_id = ? ORDER BY l.id ASC`,
      [taskId]
    );
    const links: TaskNoteLink[] = [];
    await Db.each(rs, () => {
          const l: TaskNoteLink = {
            id: Db.n(rs, 'id'),
            note_id: Db.n(rs, 'note_id'),
            title: Db.s(rs, 'title'),
            content: Db.s(rs, 'content'),
            created_at: Db.s(rs, 'created_at'),
            updated_at: Db.s(rs, 'updated_at')
          };
          links.push(l);
    });
    Db.close(rs);
    const resp: TaskNoteLinksResp = { links: links };
    return resp;
  }

  static async addLink(noteId: number, taskId: number): Promise<OkResp> {
    const rs = await Db.query('SELECT id FROM note_task WHERE note_id = ? AND task_id = ?', [noteId, taskId]);
    let exists: boolean = false;
    await Db.first(rs, () => { exists = true; });
    Db.close(rs);
    if (!exists) {
      await Db.exec('INSERT INTO note_task (note_id,task_id,created_at) VALUES (?,?,?)',
        [noteId, taskId, nowStr()]);
    }
    const r: OkResp = { ok: true };
    return r;
  }

  static async removeLink(noteId: number, taskId: number): Promise<OkResp> {
    await Db.exec('DELETE FROM note_task WHERE note_id = ? AND task_id = ?', [noteId, taskId]);
    const r: OkResp = { ok: true };
    return r;
  }

  // ───────────────────────── 搜索 ─────────────────────────

  /**
   * 本地搜索：任务 / 记录 / 日程 / 复盘四类，空格分词 AND。
   * 评分沿用工作台 lib/search.ts：标题命中 +10、标题前缀 +6、正文 +2。
   */
  static async search(q: string, kind: string): Promise<SearchResp> {
    const terms: string[] = q.trim().split(/\s+/).filter((t: string) => t.length > 0);
    const hits: SearchHit[] = [];
    const taskHits: SearchTaskHit[] = [];
    const noteHits: SearchNoteHit[] = [];

    if (terms.length > 0 && (kind === 'all' || kind === 'task')) {
      const rs = await Db.query('SELECT * FROM task');
      await Db.each(rs, () => {
            const t = Repo.readTask(rs);
            // v4.4：标签和所属项目也算可搜字段（以前搜不到「带某个标签」的任务）
            const body: string = `${t.note} ${t.tags} ${t.project}`;
            const score: number = Repo.score(t.title, body, terms);
            if (score > 0) {
              const h: SearchHit = {
                kind: 'task', id: t.id, title: t.title,
                snippet: Repo.snippet(body, terms), at: t.updated_at, score: score
              };
              hits.push(h);
              taskHits.push({ id: t.id, title: t.title, status: t.status });
            }
      });
      Db.close(rs);
    }
    if (terms.length > 0 && (kind === 'all' || kind === 'note')) {
      const rs = await Db.query('SELECT * FROM note');
      await Db.each(rs, () => {
            const n = Repo.readNote(rs);
            // v4.4：标签和来源也算可搜字段
            const nbody: string = `${n.content} ${n.tags} ${n.source}`;
            const score: number = Repo.score(n.title, nbody, terms);
            if (score > 0) {
              const h: SearchHit = {
                kind: 'note', id: n.id,
                title: n.title.length > 0 ? n.title : Repo.firstLine(n.content),
                snippet: Repo.snippet(nbody, terms), at: n.updated_at, score: score
              };
              hits.push(h);
              noteHits.push({ id: n.id, title: n.title });
            }
      });
      Db.close(rs);
    }
    if (terms.length > 0 && (kind === 'all' || kind === 'event')) {
      const rs = await Db.query('SELECT * FROM event');
      await Db.each(rs, () => {
            const e = Repo.readEvent(rs);
            const score: number = Repo.score(e.title, e.note + ' ' + e.location, terms);
            if (score > 0) {
              const h: SearchHit = {
                kind: 'event', id: e.id, title: e.title,
                snippet: Repo.snippet(e.location.length > 0 ? `${e.start_at.slice(5, 16).replace('T', ' ')} · ${e.location}` : e.note, terms),
                at: e.start_at, score: score
              };
              hits.push(h);
            }
      });
      Db.close(rs);
    }
    if (terms.length > 0 && (kind === 'all' || kind === 'review')) {
      const rs = await Db.query('SELECT * FROM review');
      await Db.each(rs, () => {
            const r: Review = {
              id: Db.n(rs, 'id'), date: Db.s(rs, 'date'),
              type: Db.s(rs, 'type') as 'daily' | 'weekly',
              did: Db.s(rs, 'did'), stuck: Db.s(rs, 'stuck'), tomorrow: Db.s(rs, 'tomorrow'),
              summary: Db.s(rs, 'summary'), ai_generated: Db.n(rs, 'ai_generated'),
              created_at: Db.s(rs, 'created_at'), updated_at: Db.s(rs, 'updated_at')
            };
            const body: string = `${r.did} ${r.stuck} ${r.tomorrow} ${r.summary}`;
            const score: number = Repo.score(r.summary, body, terms);
            if (score > 0) {
              const h: SearchHit = {
                kind: 'review', id: r.id,
                title: r.summary.length > 0 ? r.summary : `${r.date} 的复盘`,
                snippet: Repo.snippet(body, terms), at: r.date, score: score
              };
              hits.push(h);
            }
      });
      Db.close(rs);
    }

    // v4.4：算出来的分数一定要用上 —— 以前算完 score 直接扔掉，
    // 结果就是「谁在表里排前面谁就在前面」，跟匹不匹配没关系。
    // 分数高的在前，同分按时间新的在前（网页版 lib/search.ts 同口径）。
    for (let i = 0; i < hits.length; i++) {
      for (let j = i + 1; j < hits.length; j++) {
        const a: SearchHit = hits[i];
        const b: SearchHit = hits[j];
        const swap: boolean = b.score > a.score || (b.score === a.score && b.at > a.at);
        if (swap) {
          hits[i] = b;
          hits[j] = a;
        }
      }
    }
    // v4.4：分项计数按**全部**命中算。以前是拿截断后的 60 条去数，
    // 而「共 N 条」用的是未截断的数 ⇒ 分项加起来跟总数对不上。
    const counts: number[] = [0, 0, 0, 0];
    for (const h of hits) {
      if (h.kind === 'task') { counts[0] += 1; }
      else if (h.kind === 'note') { counts[1] += 1; }
      else if (h.kind === 'event') { counts[2] += 1; }
      else if (h.kind === 'review') { counts[3] += 1; }
    }
    const resp: SearchResp = {
      hits: hits.slice(0, 60),
      total: hits.length,
      counts: counts,
      tasks: taskHits.slice(0, 8),
      notes: noteHits.slice(0, 8)
    };
    return resp;
  }

  /**
   * v4.4：评分照抄网页版 lib/search.ts:42-53 —— 标题里出现 +10，
   * 标题开头再 +6（是「再」不是「或者」，以前写成 else-if，+6 永远拿不到），
   * 正文里出现 +2。所有词都要命中（AND）。
   */
  private static score(title: string, body: string, terms: string[]): number {
    const t: string = title.toLowerCase();
    const b: string = body.toLowerCase();
    let total: number = 0;
    for (const term of terms) {
      const q: string = term.toLowerCase();
      let s: number = 0;
      if (t.indexOf(q) >= 0) { s += 10; }
      if (t.startsWith(q)) { s += 6; }
      if (b.indexOf(q) >= 0) { s += 2; }
      if (s === 0) { return 0; }   // 所有词都要命中（AND）
      total += s;
    }
    return total;
  }

  private static snippet(body: string, terms: string[]): string {
    const b: string = body.replace(/\s+/g, ' ').trim();
    if (b.length === 0) { return ''; }
    const low: string = b.toLowerCase();
    let at: number = -1;
    for (const term of terms) {
      const i: number = low.indexOf(term.toLowerCase());
      if (i >= 0 && (at < 0 || i < at)) { at = i; }
    }
    if (at < 0) { return b.substring(0, 120); }
    const start: number = Math.max(0, at - 18);
    return (start > 0 ? '…' : '') + b.substring(start, start + 120);
  }

  private static firstLine(content: string): string {
    const s: string = content.replace(/\s+/g, ' ').trim();
    return s.substring(0, 30);
  }

  // ───────────────────────── 统计 / 备份 ─────────────────────────

  /** 本地数据库概况，给设置页显示 */
  static async stats(): Promise<LocalStats> {
    const s: LocalStats = {
      tasks: await Db.countRows('task'),
      events: await Db.countRows('event'),
      notes: await Db.countRows('note'),
      projects: await Db.countRows('project'),
      reviews: await Db.countRows('review'),
      habits: await Db.countRows('habit')
    };
    return s;
  }

  /** 导出全部数据为 JSON（带回车号，便于跨设备搬运） */
  static async exportJson(): Promise<string> {
    const payload: ExportPayload = {
      app: 'personal-workbench-harmony',
      version: 4,
      exported_at: nowStr(),
      tasks: await Repo.tasks(),
      events: await Repo.events(),
      notes: await Repo.notes(true),
      projects: await Repo.projects(),
      reviews: await Repo.reviews(),
      habits: await Repo.habits(),
      settings: await Repo.settings(),
      links: await Repo.allLinks()
    };
    return JSON.stringify(payload);
  }

  /**
   * 从 JSON 导入（覆盖式）。
   *
   * v4.4 改成「先校验、后清空」，而且整段包在事务里：
   * 之前 clearAll() 排在最前面，粘一个 123 或网页端导出的 JSON 就会先清库再报错 —— 数据没了。
   * 现在任何一步不对都直接回滚，原数据一条不动。
   */
  static async importJson(json: string): Promise<ImportSummary> {
    let w: WebExport | null = null;
    try {
      w = JSON.parse(json) as WebExport;
    } catch (e) {
      throw new Error('这不是备份文件（不是合法的 JSON），原数据没有动');
    }
    if (w === null || w === undefined || typeof w !== 'object') {
      throw new Error('这不是备份文件（内容不对），原数据没有动');
    }
    let data: ExportPayload;
    if (w.app === 'personal-workbench-harmony') {
      data = JSON.parse(json) as ExportPayload;
    } else {
      // v4.7：网页端（个人工作台 Next.js）导出的备份也能导进来 —— 单数 key、无 app 字段
      const conv: ExportPayload | null = Repo.fromWebExport(w);
      if (conv === null) {
        throw new Error('这不是本工作台的备份文件，原数据没有动');
      }
      data = conv;
    }
    if (!Array.isArray(data.tasks) || !Array.isArray(data.events) || !Array.isArray(data.notes)
      || !Array.isArray(data.projects) || !Array.isArray(data.reviews)) {
      throw new Error('备份文件内容不完整，原数据没有动');
    }
    const total: number = data.tasks.length + data.events.length + data.notes.length
      + data.projects.length + data.reviews.length;
    if (total === 0) {
      throw new Error('备份里没有内容，原数据没有动');
    }
    let n: number = 0;
    await Db.beginTx();
    try {
      await Repo.clearAll();
      for (const t of data.tasks) {
        await Repo.insertTaskRow(t);
        n += 1;
      }
      for (const e of data.events) {
        await Repo.insertEventRow(e);
        n += 1;
      }
      for (const t of data.notes) {
        await Repo.insertNoteRow(t);
        n += 1;
      }
      for (const t of data.projects) {
        await Repo.insertProjectRow(t);
        n += 1;
      }
      for (const r of data.reviews) {
        await Repo.insertReviewRow(r);
        n += 1;
      }
      if (data.habits !== undefined && data.habits !== null
        && Array.isArray(data.habits.habits)) {
        for (const h of data.habits.habits) {
          await Repo.insertHabitRow(h);
        }
      }
      // 记录 ↔ 任务的关联也要一起带走，否则恢复完关联全没了
      if (data.links !== undefined && data.links !== null && Array.isArray(data.links)) {
        for (const l of data.links) {
          await Db.exec('INSERT INTO note_task (note_id, task_id, created_at) VALUES (?,?,?)',
            [l.note_id, l.task_id, nowStr()]);
        }
      }
      // 项目名回填：网页端导出的任务只有 project_id，名字得从项目表里补回来
      await Db.exec(
        `UPDATE task SET project = (SELECT name FROM project WHERE project.id = task.project_id)
          WHERE project_id IS NOT NULL AND (project IS NULL OR project = '')`
      );
      // 称呼（user_name）也要恢复
      if (data.settings !== undefined && data.settings !== null
        && typeof data.settings.user_name === 'string' && data.settings.user_name.length > 0) {
        await Db.setSetting('user_name', data.settings.user_name);
      }
      await Db.commitTx();
    } catch (e) {
      await Db.rollbackTx();
      throw new Error('恢复失败，原数据没有动');
    }
    const summary: ImportSummary = { count: n };
    return summary;
  }

  /**
   * 网页端导出的备份 → App 自己的备份格式。
   *
   * 网页端（个人工作台 Next.js）导出的是单数 key、没有 app 字段：
   *   { exported_at, version:1, task:[], event:[], note:[], review:[], project:[], note_task:[], settings:{} }
   * App 自己是复数 key + app: 'personal-workbench-harmony'。
   * 两边字段基本同名，只是网页端少几个新列（tags / repeat_rule / remind_min / archived / target_date）。
   * 返回 null 表示「这份 JSON 不像网页端导出的备份」。
   */
  private static fromWebExport(w: WebExport): ExportPayload | null {
    const hasWeb: boolean = Array.isArray(w.task) || Array.isArray(w.event) || Array.isArray(w.note)
      || Array.isArray(w.review) || Array.isArray(w.project) || Array.isArray(w.note_task);
    if (!hasWeb) {
      return null;
    }
    const tasks: Task[] = [];
    const wt: WebTask[] = w.task === undefined ? [] : w.task;
    for (let i = 0; i < wt.length; i++) {
      const r = wt[i];
      const t: Task = {
        id: Repo.wNum(r.id, i + 1),
        title: Repo.wStr(r.title, '导入任务'),
        note: Repo.wStr(r.note, ''),
        status: Repo.wStatus(r.status),
        priority: Repo.wPriority(r.priority),
        area: Repo.wArea(r.area),
        project_id: Repo.wNumOrNull(r.project_id),
        due_date: Repo.wStrOrNull(r.due_date),
        scheduled_start: Repo.wStrOrNull(r.scheduled_start),
        scheduled_end: Repo.wStrOrNull(r.scheduled_end),
        estimate_min: Repo.wNumOrNull(r.estimate_min),
        done_at: Repo.wStrOrNull(r.done_at),
        sort: Repo.wNum(r.sort, 0),
        created_at: Repo.wStr(r.created_at, nowStr()),
        updated_at: Repo.wStr(r.updated_at, nowStr()),
        project: '',
        tags: '',
        repeat_rule: 'none',
        remind_min: null
      };
      tasks.push(t);
    }
    const events: EventItem[] = [];
    const we: WebEvent[] = w.event === undefined ? [] : w.event;
    for (let i = 0; i < we.length; i++) {
      const r = we[i];
      const e: EventItem = {
        id: Repo.wNum(r.id, i + 1),
        title: Repo.wStr(r.title, '导入日程'),
        start_at: Repo.wStr(r.start_at, nowStr()),
        end_at: Repo.wStrOrNull(r.end_at),
        all_day: Repo.wNum(r.all_day, 0),
        location: Repo.wStr(r.location, ''),
        note: Repo.wStr(r.note, ''),
        created_at: Repo.wStr(r.created_at, nowStr()),
        repeat_rule: 'none',
        remind_min: null
      };
      events.push(e);
    }
    const notes: Note[] = [];
    const wn: WebNote[] = w.note === undefined ? [] : w.note;
    for (let i = 0; i < wn.length; i++) {
      const r = wn[i];
      const n: Note = {
        id: Repo.wNum(r.id, i + 1),
        title: Repo.wStr(r.title, ''),
        content: Repo.wStr(r.content, ''),
        source: Repo.wStr(r.source, '导入'),
        pinned: Repo.wNum(r.pinned, 0),
        created_at: Repo.wStr(r.created_at, nowStr()),
        updated_at: Repo.wStr(r.updated_at, nowStr()),
        tags: '',
        archived: 0,
        project_id: null
      };
      notes.push(n);
    }
    const projects: Project[] = [];
    const wp: WebProject[] = w.project === undefined ? [] : w.project;
    for (let i = 0; i < wp.length; i++) {
      const r = wp[i];
      const p: Project = {
        id: Repo.wNum(r.id, i + 1),
        name: Repo.wStr(r.name, '导入项目'),
        color: Repo.wStr(r.color, '#9B8AE6'),
        area: Repo.wArea(r.area),
        status: Repo.wStr(r.status, 'active'),
        note: Repo.wStr(r.note, ''),
        sort: Repo.wNum(r.sort, 0),
        created_at: Repo.wStr(r.created_at, nowStr()),
        target_date: null,
        total: 0,
        done: 0
      };
      projects.push(p);
    }
    const reviews: Review[] = [];
    const wr: WebReview[] = w.review === undefined ? [] : w.review;
    for (let i = 0; i < wr.length; i++) {
      const r = wr[i];
      const v: Review = {
        id: Repo.wNum(r.id, i + 1),
        date: Repo.wStr(r.date, D.today()),
        type: r.type === 'weekly' ? 'weekly' : 'daily',
        did: Repo.wStr(r.did, ''),
        stuck: Repo.wStr(r.stuck, ''),
        tomorrow: Repo.wStr(r.tomorrow, ''),
        summary: Repo.wStr(r.summary, ''),
        ai_generated: Repo.wNum(r.ai_generated, 0),
        created_at: Repo.wStr(r.created_at, nowStr()),
        updated_at: Repo.wStr(r.updated_at, nowStr())
      };
      reviews.push(v);
    }
    const links: NoteLinkPair[] = [];
    const wl: WebLink[] = w.note_task === undefined ? [] : w.note_task;
    for (let i = 0; i < wl.length; i++) {
      const r = wl[i];
      const nId: number = Repo.wNum(r.note_id, 0);
      const tId: number = Repo.wNum(r.task_id, 0);
      if (nId > 0 && tId > 0) {
        links.push({ note_id: nId, task_id: tId });
      }
    }
    const webSettings: WebSettings = w.settings === undefined ? {} : w.settings;
    const settings: SettingsResp = {
      user_name: Repo.wStr(webSettings.user_name, ''),
      ai_base_url: '',
      ai_model: '',
      ai_key_set: false
    };
    const habits: HabitsResp = {
      today: D.today(),
      days: [],
      habits: []
    };
    const payload: ExportPayload = {
      app: 'personal-workbench-harmony',
      version: 4,
      exported_at: nowStr(),
      tasks: tasks,
      events: events,
      notes: notes,
      projects: projects,
      reviews: reviews,
      habits: habits,
      settings: settings,
      links: links
    };
    return payload;
  }

  private static wStr(v: string | undefined, d: string): string {
    return (typeof v === 'string' && v.length > 0) ? v : d;
  }

  private static wStrOrNull(v: string | undefined | null): string | null {
    return (typeof v === 'string' && v.length > 0) ? v : null;
  }

  private static wNum(v: number | undefined, d: number): number {
    return (typeof v === 'number') ? v : d;
  }

  private static wNumOrNull(v: number | undefined | null): number | null {
    return (typeof v === 'number') ? v : null;
  }

  private static wStatus(v: string | undefined): TaskStatus {
    if (v === 'doing' || v === 'done') {
      return v;
    }
    return 'todo';
  }

  private static wPriority(v: string | undefined): Priority {
    if (v === 'high' || v === 'low') {
      return v;
    }
    return 'med';
  }

  private static wArea(v: string | undefined): Area {
    if (v === 'side' || v === 'media' || v === 'study' || v === 'life') {
      return v;
    }
    return 'work';
  }

  /** 导出用的关联清单（记录 ↔ 任务） */
  // ── v4.12：任务 ↔ 日程 关联 ──

  /** 建一条关联（已存在就不重复建） */
  static async linkTaskEvent(taskId: number, eventId: number): Promise<void> {
    if (taskId <= 0 || eventId <= 0) { return; }
    const rs = await Db.query('SELECT id FROM task_event WHERE task_id = ? AND event_id = ?', [taskId, eventId]);
    let exists: boolean = false;
    try {
      exists = rs.goToFirstRow();
    } catch (e) {
      // goToFirstRow 在空结果集上会抛异常，视为「没有这一行」
      exists = false;
    }
    Db.close(rs);
    if (exists) { return; }
    await Db.exec('INSERT INTO task_event (task_id, event_id, created_at) VALUES (?,?,?)', [taskId, eventId, D.now()]);
  }

  /** 拆一条关联 */
  static async unlinkTaskEvent(taskId: number, eventId: number): Promise<void> {
    if (taskId <= 0 || eventId <= 0) { return; }
    await Db.exec('DELETE FROM task_event WHERE task_id = ? AND event_id = ?', [taskId, eventId]);
  }

  /** 全部关联 */
  static async taskEventLinks(): Promise<TaskEventLink[]> {
    const out: TaskEventLink[] = [];
    const rs = await Db.query('SELECT task_id AS task_id, event_id AS event_id FROM task_event');
    await Db.each(rs, () => {
      out.push({ task_id: rs.getLong(0), event_id: rs.getLong(1) });
    });
    Db.close(rs);
    return out;
  }

  /** 某个任务关联的日程 id 列表 */
  static async eventIdsOfTask(taskId: number): Promise<number[]> {
    const out: number[] = [];
    const rs = await Db.query('SELECT event_id FROM task_event WHERE task_id = ?', [taskId]);
    await Db.each(rs, () => { out.push(rs.getLong(0)); });
    Db.close(rs);
    return out;
  }

  static async allLinks(): Promise<NoteLinkPair[]> {
    const rs = await Db.query('SELECT note_id AS note_id, task_id AS task_id FROM note_task');
    const out: NoteLinkPair[] = [];
    await Db.each(rs, () => {
      out.push({ note_id: Db.n(rs, 'note_id'), task_id: Db.n(rs, 'task_id') } as NoteLinkPair);
    });
    return out;
  }

  private static async insertTaskRow(t: Task): Promise<void> {
    await Db.exec(
      `INSERT INTO task (id,title,note,status,priority,area,project_id,due_date,scheduled_start,
        scheduled_end,estimate_min,done_at,sort,created_at,updated_at,project,tags,repeat_rule,remind_min)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        t.id, t.title, t.note, t.status, t.priority, t.area, t.project_id, t.due_date,
        t.scheduled_start, t.scheduled_end, t.estimate_min, t.done_at, t.sort,
        t.created_at, t.updated_at, t.project, t.tags, t.repeat_rule, t.remind_min
      ]
    );
  }

  private static async insertEventRow(e: EventItem): Promise<void> {
    await Db.exec(
      `INSERT INTO event (id,title,start_at,end_at,all_day,location,note,created_at,repeat_rule,remind_min)
       VALUES (?,?,?,?,?,?,?,?,?,?)`,
      [
        e.id, e.title, e.start_at, e.end_at, e.all_day, e.location, e.note,
        e.created_at, e.repeat_rule, e.remind_min
      ]
    );
  }

  private static async insertNoteRow(n: Note): Promise<void> {
    await Db.exec(
      `INSERT INTO note (id,title,content,source,pinned,created_at,updated_at,tags,archived,project_id)
       VALUES (?,?,?,?,?,?,?,?,?,?)`,
      [
        n.id, n.title, n.content, n.source, n.pinned, n.created_at, n.updated_at,
        n.tags, n.archived, n.project_id
      ]
    );
  }

  private static async insertProjectRow(p: Project): Promise<void> {
    await Db.exec(
      `INSERT INTO project (id,name,color,area,status,note,sort,target_date,created_at)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      [p.id, p.name, p.color, p.area, p.status, p.note, p.sort, p.target_date, p.created_at]
    );
  }

  private static async insertReviewRow(r: Review): Promise<void> {
    await Db.exec(
      `INSERT INTO review (id,date,type,did,stuck,tomorrow,summary,ai_generated,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?)`,
      [
        r.id, r.date, r.type, r.did, r.stuck, r.tomorrow, r.summary, r.ai_generated,
        r.created_at, r.updated_at
      ]
    );
  }

  private static async insertHabitRow(h: HabitView): Promise<void> {
    await Db.exec(
      'INSERT INTO habit (id,name,color,sort,archived,created_at) VALUES (?,?,?,?,?,?)',
      [h.id, h.name, h.color, h.sort, h.archived, h.created_at]
    );
    for (const d of h.logs) {
      await Db.exec('INSERT INTO habit_log (habit_id,date,created_at) VALUES (?,?,?)',
        [h.id, d, nowStr()]);
    }
  }

  /** 清空所有业务数据（设置保留） */
  static async clearAll(): Promise<OkResp> {
    // 标记「这个库已经初始化过了」：清空之后下次冷启动不该把示例数据又铺回来
    await Db.setSetting('initialized', '1');
    await Db.exec('DELETE FROM task');
    await Db.exec('DELETE FROM event');
    await Db.exec('DELETE FROM note');
    await Db.exec('DELETE FROM note_task');
    await Db.exec('DELETE FROM review');
    await Db.exec('DELETE FROM project');
    await Db.exec('DELETE FROM habit');
    await Db.exec('DELETE FROM habit_log');
    const r: OkResp = { ok: true };
    return r;
  }

  /** 首次启动：放一点点示例数据，别让 App 打开是空的
   *  v4.4：只在「这个库从来没初始化过」时铺一次。
   *  用户主动清空数据后，冷启动不该把示例数据又诈尸回来（和设置页的文案要对得上）。
   */
  static async seedIfEmpty(): Promise<boolean> {
    const initialized: string = await Db.getSetting('initialized', '');
    if (initialized === '1') { return false; }
    const n: number = await Db.countRows('task');
    if (n > 0) {
      await Db.setSetting('initialized', '1');
      return false;
    }
    const today: string = Db.today();
    const tomorrow: string = D.addDays(today, 1);
    const now = nowStr();

    await Db.exec(
      `INSERT INTO task (title,note,status,priority,area,due_date,scheduled_start,scheduled_end,
        estimate_min,project,project_id,tags,repeat_rule,remind_min,done_at,sort,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      ['熟悉一下这个工作台', '先看看首页、任务面板、日历和记录灵感', 'todo', 'high', 'work',
        today, null, null, 30, '', null, '', 'none', null, null, 0, now, now]
    );
    await Db.exec(
      `INSERT INTO task (title,note,status,priority,area,due_date,scheduled_start,scheduled_end,
        estimate_min,project,project_id,tags,repeat_rule,remind_min,done_at,sort,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      ['写一条灵感试试', '在右下角那个按钮里随手记一条', 'todo', 'med', 'life',
        tomorrow, null, null, 15, '', null, '', 'none', null, null, 1, now, now]
    );
    await Db.exec(
      `INSERT INTO event (title,start_at,end_at,all_day,location,note,created_at,repeat_rule,remind_min)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      ['今天的时间', `${today}T20:00`, `${today}T21:00`, 0, '', '', now, 'none', 10]
    );
    await Db.exec(
      `INSERT INTO note (title,content,source,tags,archived,pinned,project_id,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      ['欢迎使用', '所有数据都存在这台手机上，不上传、不联网。想带走就导出备份文件。',
        '灵感', '', 0, 1, null, now, now]
    );
    await Db.exec('INSERT INTO habit (name,color,sort,archived,created_at) VALUES (?,?,?,0,?)',
      ['每天动一动', '#3AC8C2', 1, now]);
    await Db.exec('INSERT INTO habit (name,color,sort,archived,created_at) VALUES (?,?,?,0,?)',
      ['早睡', '#A78BFA', 2, now]);
    await Db.setSetting('initialized', '1');
    return true;
  }
}

export interface LocalStats {
  tasks: number;
  events: number;
  notes: number;
  projects: number;
  reviews: number;
  habits: number;
}

export interface ImportSummary { count: number }

export interface ExportPayload {
  app: string;
  version: number;
  exported_at: string;
  tasks: Task[];
  events: EventItem[];
  notes: Note[];
  projects: Project[];
  reviews: Review[];
  habits: HabitsResp;
  settings: SettingsResp;
  links: NoteLinkPair[];
}

/** 记录 ↔ 任务的关联（备份里一起带走） */
export interface NoteLinkPair {
  note_id: number;
  task_id: number;
}

/** 网页端（个人工作台 Next.js）导出的备份：单数 key、没有 app 字段 */
interface WebExport {
  app?: string;
  exported_at?: string;
  version?: number;
  task?: WebTask[];
  event?: WebEvent[];
  note?: WebNote[];
  review?: WebReview[];
  project?: WebProject[];
  note_task?: WebLink[];
  settings?: WebSettings;
}

interface WebTask {
  id?: number;
  title?: string;
  note?: string;
  status?: string;
  priority?: string;
  area?: string;
  project_id?: number | null;
  due_date?: string | null;
  scheduled_start?: string | null;
  scheduled_end?: string | null;
  estimate_min?: number | null;
  done_at?: string | null;
  sort?: number;
  created_at?: string;
  updated_at?: string;
}

interface WebEvent {
  id?: number;
  title?: string;
  start_at?: string;
  end_at?: string | null;
  all_day?: number;
  location?: string;
  note?: string;
  created_at?: string;
}

interface WebNote {
  id?: number;
  title?: string;
  content?: string;
  source?: string;
  pinned?: number;
  created_at?: string;
  updated_at?: string;
}

interface WebReview {
  id?: number;
  date?: string;
  type?: string;
  did?: string;
  stuck?: string;
  tomorrow?: string;
  summary?: string;
  ai_generated?: number;
  created_at?: string;
  updated_at?: string;
}

interface WebProject {
  id?: number;
  name?: string;
  color?: string;
  area?: string;
  status?: string;
  note?: string;
  sort?: number;
  created_at?: string;
}

interface WebLink {
  note_id?: number;
  task_id?: number;
}

interface WebSettings {
  user_name?: string;
}
