// entry/src/main/ets/api/Endpoints.ets
// 所有路径集中在这里，和「个人工作台」 app/api/*/route.ts 一一对应。
// 路径里不写域名，域名由 Http.baseUrl 决定（可在设置页改成内网地址）。

export class Api {
  static readonly auth: string = '/api/auth';
  static readonly health: string = '/api/health';
  static readonly tasks: string = '/api/tasks';
  static readonly events: string = '/api/events';
  static readonly notes: string = '/api/notes';
  static readonly projects: string = '/api/projects';
  static readonly reviews: string = '/api/reviews';
  static readonly habits: string = '/api/habits';
  static readonly habitLog: string = '/api/habits/log';
  static readonly reminders: string = '/api/reminders';
  static readonly settings: string = '/api/settings';
  static readonly search: string = '/api/search';
  static readonly links: string = '/api/links';
  static readonly exportJson: string = '/api/export';
  static readonly exportDb: string = '/api/export-db';

  static task(id: number): string { return `/api/tasks/${id}`; }
  static event(id: number): string { return `/api/events/${id}`; }
  static note(id: number): string { return `/api/notes/${id}`; }
  static project(id: number): string { return `/api/projects/${id}`; }
  static review(id: number): string { return `/api/reviews/${id}`; }
  static habit(id: number): string { return `/api/habits/${id}`; }

  /** 带查询串的列表 */
  static tasksQuery(status: string, q: string, project: string): string {
    const parts: string[] = [];
    if (status) { parts.push(`status=${encodeURIComponent(status)}`); }
    if (q) { parts.push(`q=${encodeURIComponent(q)}`); }
    if (project) { parts.push(`project=${encodeURIComponent(project)}`); }
    return parts.length ? `/api/tasks?${parts.join('&')}` : '/api/tasks';
  }

  static eventsQuery(from: string, to: string): string {
    return `/api/events?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`;
  }

  static notesQuery(q: string, archived: boolean): string {
    const parts: string[] = [];
    if (q) { parts.push(`q=${encodeURIComponent(q)}`); }
    if (archived) { parts.push('archived=1'); }
    return parts.length ? `/api/notes?${parts.join('&')}` : '/api/notes';
  }

  static searchQuery(q: string, kind: string): string {
    return `/api/search?q=${encodeURIComponent(q)}&kind=${encodeURIComponent(kind)}`;
  }
}
