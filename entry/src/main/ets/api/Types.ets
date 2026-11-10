// entry/src/main/ets/api/Types.ets
// 严格对齐「个人工作台」 lib/db.ts 的表结构。字段名、可空性一模一样，JSON 可直接反序列化。

export type Area = 'work' | 'side' | 'media' | 'study' | 'life';
export type Priority = 'high' | 'med' | 'low';
export type TaskStatus = 'todo' | 'doing' | 'done';
export type RepeatRule = 'none' | 'daily' | 'weekdays' | 'weekly' | 'monthly';

export interface Task {
  id: number;
  title: string;
  note: string;
  status: TaskStatus;
  priority: Priority;
  area: Area;
  project_id: number | null;
  due_date: string | null;            // yyyy-MM-dd
  scheduled_start: string | null;     // yyyy-MM-ddTHH:mm
  scheduled_end: string | null;
  estimate_min: number | null;
  done_at: string | null;
  sort: number;
  created_at: string;
  updated_at: string;
  project: string;                    // 迁移列，自由文本项目名
  tags: string;                       // 逗号分隔
  repeat_rule: RepeatRule;
  remind_min: number | null;          // 提前多少分钟提醒
}

export interface EventItem {
  id: number;
  title: string;
  start_at: string;                   // yyyy-MM-ddTHH:mm
  end_at: string | null;
  all_day: number;                    // 0 | 1
  location: string;
  note: string;
  created_at: string;
  repeat_rule: RepeatRule;
  remind_min: number | null;
}

/** v4.12：任务 ↔ 日程 的关联 */
export interface TaskEventLink {
  task_id: number;
  event_id: number;
}

export interface Note {
  id: number;
  title: string;
  content: string;
  source: string;
  pinned: number;
  created_at: string;
  updated_at: string;
  tags: string;
  archived: number;
  project_id: number | null;
}

export interface Project {
  id: number;
  name: string;
  color: string;
  area: Area;
  status: string;
  note: string;
  sort: number;
  created_at: string;
  target_date: string | null;
  total: number;                      // 后端子查询算好的任务数
  done: number;                       // 已完成数
}

export interface Review {
  id: number;
  date: string;                       // yyyy-MM-dd
  type: 'daily' | 'weekly';
  did: string;
  stuck: string;
  tomorrow: string;
  summary: string;
  ai_generated: number;
  created_at: string;
  updated_at: string;
}

export interface Habit {
  id: number;
  name: string;
  color: string;
  sort: number;
  archived: number;
  created_at: string;
}

export interface HabitView extends Habit {
  logs: string[];                     // 最近 365 天已打卡的日期
  streak: number;                     // 当前连续天数（今天没打卡就从昨天往前数）
  bestStreak: number;                 // 历史最长连续天数
  doneToday: boolean;
  weekDone: number;                   // 最近 7 天打卡几天
}

export interface ReminderItem {
  kind: 'task' | 'event';
  id: number;
  title: string;
  at: string;
  priority: Priority;
  overdue: boolean;
  remindAt?: string;
}

export interface StoredLink {
  id: number;
  note_id: number;
  task_id: number;
}

/** GET /api/links?note=N 的返回行（join 了 task） */
export interface NoteLink {
  id: number;
  created_at: string;
  task_id: number;
  title: string;
  status: string;
  due_date: string | null;
  priority: string;
  area: string;
}

export interface NoteLinksResp { links: NoteLink[] }

/** GET /api/links?task=N 的返回行 */
export interface TaskNoteLink {
  id: number;
  note_id: number;
  title: string;
  content: string;
  created_at: string;
  updated_at: string;
}
export interface TaskNoteLinksResp { links: TaskNoteLink[] }

export interface SearchHit {
  kind: string;
  id: number;
  title: string;
  snippet: string;
  at: string;
  score: number;          // v4.4：算出来的分要留着排序用（以前算完就扔了）
}

// ── 请求/响应的包装类型（后端不统一，必须逐个对应）──
export interface TasksResp { tasks: Task[] }
export interface TaskCreateResp { id: number; task: Task }
export interface TaskPatchResp { task: Task; next?: Task | null }
export interface EventsResp { events: EventItem[] }
export interface EventCreateResp { event: EventItem }
export interface NotesResp { notes: Note[] }
export interface NoteCreateResp { note: Note }
export interface NotePatchResp { note: Note }
export interface ProjectsResp { projects: Project[] }
export interface ProjectCreateResp { project: Project }
export interface ProjectPatchResp { project: Project }
export interface ReviewsResp { reviews: Review[] }
export interface HabitsResp {
  today: string;
  days: string[];
  habits: HabitView[];
}
export interface HabitCreateResp extends HabitsResp { habit: HabitView }
export interface HabitLogResp extends HabitsResp {
  done: boolean;
  date: string;
}
export interface RemindersResp { items: ReminderItem[]; now: string }
export interface OkResp { ok: boolean }
export interface SettingsResp {
  user_name: string;
  ai_base_url: string;
  ai_model: string;
  ai_key_set: boolean;
}
export interface AuthStateResp { hasPassword: boolean; authed: boolean }
export interface HealthResp {
  ok: boolean;
  sha?: string;
  built?: string;
  at?: string;
}
export interface LinksResp { links: StoredLink[] }
export interface SearchTaskHit { id: number; title: string; status: string }
export interface SearchNoteHit { id: number; title: string }
export interface SearchResp {
  hits: SearchHit[];
  total: number;
  /** 各类别的命中数（按全部命中算，不是按截断后的 60 条算） */
  counts: number[];
  tasks: SearchTaskHit[];
  notes: SearchNoteHit[];
}

// 写操作的请求体（zod schema 的字段都是 optional，这里按需挑）
export interface TaskUpdate {
  title?: string;
  note?: string;
  status?: TaskStatus;
  priority?: Priority;
  area?: Area;
  due_date?: string | null;
  scheduled_start?: string | null;
  scheduled_end?: string | null;
  estimate_min?: number | null;
  project?: string;
  project_id?: number | null;
  tags?: string;
  sort?: number;
  repeat_rule?: RepeatRule;
  remind_min?: number | null;
}

export interface TaskCreate {
  title: string;
  note?: string;
  area?: Area;
  priority?: Priority;
  status?: TaskStatus;
  due_date?: string | null;
  scheduled_start?: string | null;
  scheduled_end?: string | null;
  estimate_min?: number | null;
  project?: string;
  project_id?: number | null;
  tags?: string;
  repeat_rule?: RepeatRule;
  remind_min?: number | null;
}

export interface EventCreate {
  title: string;
  start_at: string;
  end_at?: string | null;
  all_day?: number;
  location?: string;
  note?: string;
  repeat_rule?: RepeatRule;
  remind_min?: number | null;
}

/** PATCH /api/events/[id] 与 PATCH /api/tasks/[id] 一样：字段全部可选 */
export interface EventUpdate {
  title?: string;
  start_at?: string;
  end_at?: string | null;
  all_day?: number;
  location?: string;
  note?: string;
  repeat_rule?: RepeatRule;
  remind_min?: number | null;
}
export interface EventPatchResp { event: EventItem }

/** POST /api/ai {action:"parse"} */
export interface AiDraft {
  title: string;
  area: Area;
  priority: Priority;
  due_date?: string | null;
}
export interface AiParseResp { tasks?: AiDraft[] }
export interface AiParseReq { action: string; text: string }

export interface NoteCreate {
  title?: string;
  content: string;
  source?: string;
}

export interface NoteUpdate {
  title?: string;
  content?: string;
  source?: string;
  pinned?: number;
  archived?: number;
  tags?: string;
  project_id?: number | null;
}

export interface ProjectCreate {
  name: string;
  color?: string;
  area?: Area;
  note?: string;
  target_date?: string | null;
}

/** PATCH /api/projects/[id]（本地库同款） */
export interface ProjectUpdate {
  name?: string;
  color?: string;
  area?: Area;
  status?: string;
  note?: string;
  sort?: number;
  target_date?: string | null;
}

/** PATCH /api/habits/[id]（本地库同款） */
export interface HabitUpdate {
  name?: string;
  color?: string;
  sort?: number;
  archived?: number;
}

export interface ReviewSave {
  date?: string;
  type?: 'daily' | 'weekly';
  did?: string;
  stuck?: string;
  tomorrow?: string;
  summary?: string;
}

export interface HabitCreate { name: string; color?: string }
export interface HabitLogReq { habit_id: number; date?: string }
export interface SettingsPatch {
  user_name?: string;
  ai_base_url?: string;
  ai_model?: string;
  ai_key?: string;
}
export interface LoginReq { password: string; confirm?: string }
export interface PasswordChangeReq { current: string; password: string }
