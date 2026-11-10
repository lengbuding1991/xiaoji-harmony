// entry/src/main/ets/utils/DateUtil.ets
// 工作台的时间字段是「本地墙上时间字符串」，不是 UTC ISO。
// 绝对不要用 new Date().toISOString()，会差 8 小时（工作台源码 todayLocal() 就是为此写的）。

export class D {
  /** 补零 */
  static p(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  /** 本地日期 yyyy-MM-dd */
  static today(): string {
    const d = new Date();
    return `${d.getFullYear()}-${D.p(d.getMonth() + 1)}-${D.p(d.getDate())}`;
  }

  /** 本地日期时间 yyyy-MM-ddTHH:mm */
  static now(): string {
    const d = new Date();
    return `${D.today()}T${D.p(d.getHours())}:${D.p(d.getMinutes())}`;
  }

  /** 从 yyyy-MM-ddTHH:mm 解析成 Date（按本地时区，不是 UTC） */
  static parse(s: string): Date {
    const y = Number(s.slice(0, 4));
    const mo = Number(s.slice(5, 7)) - 1;
    const da = Number(s.slice(8, 10));
    const h = s.length >= 13 ? Number(s.slice(11, 13)) : 0;
    const mi = s.length >= 16 ? Number(s.slice(14, 16)) : 0;
    return new Date(y, mo, da, h, mi, 0, 0);   // 注意：这是本地时区构造
  }

  /** 只取日期部分 */
  static dateOf(s: string | null): string {
    return s ? s.slice(0, 10) : '';
  }

  /** 只取时间部分 HH:mm */
  static timeOf(s: string | null): string {
    return s && s.length >= 16 ? s.slice(11, 16) : '';
  }

  /** 加 n 天，返回 yyyy-MM-dd */
  static addDays(dateStr: string, n: number): string {
    const d = D.parse(dateStr);
    d.setDate(d.getDate() + n);
    return `${d.getFullYear()}-${D.p(d.getMonth() + 1)}-${D.p(d.getDate())}`;
  }

  /** 本周一（工作台用周一为一周开始，对齐 date-fns 的 weekStartsOn:1） */
  static weekStart(): string {
    const d = new Date();
    const wd = d.getDay();               // 0=周日
    const diff = wd === 0 ? -6 : 1 - wd;
    d.setDate(d.getDate() + diff);
    return `${d.getFullYear()}-${D.p(d.getMonth() + 1)}-${D.p(d.getDate())}`;
  }

  /** 最近 n 天，从早到晚，返回 yyyy-MM-dd 数组 */
  static lastDays(n: number): string[] {
    const out: string[] = [];
    for (let i = n - 1; i >= 0; i--) {
      out.push(D.addDays(D.today(), -i));
    }
    return out;
  }

  /** 相对时间：刚刚 / 3 分钟前 / 昨天 / 11-06 */
  static human(s: string): string {
    if (!s) {
      return '';
    }
    const t = D.parse(s).getTime();
    const now = Date.now();
    const diff = now - t;
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)} 分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)} 小时前`;
    }
    if (diff < 172800000) {
      return '昨天';
    }
    return s.slice(5, 10);
  }

  /** 月份网格：周一为第一列，0 表示补白 */
  static monthGrid(year: number, month: number): number[] {
    const first = new Date(year, month - 1, 1);
    const wd = first.getDay();                      // 0=周日
    const lead = wd === 0 ? 6 : wd - 1;            // 周一第一列
    const days = new Date(year, month, 0).getDate();
    const out: number[] = [];
    for (let i = 0; i < lead; i++) { out.push(0); }
    for (let d = 1; d <= days; d++) { out.push(d); }
    while (out.length % 7 !== 0) { out.push(0); }
    return out;
  }

  static monthLabel(year: number, month: number): string {
    return `${year} 年 ${month} 月`;
  }

  static dayLabel(dateStr: string): string {
    const mo = Number(dateStr.slice(5, 7));
    const da = Number(dateStr.slice(8, 10));
    return `${mo} 月 ${da} 日`;
  }

  static weekdayLabel(i: number): string {
    const names: string[] = ['一', '二', '三', '四', '五', '六', '日'];
    return names[i] ? names[i] : '';
  }

  static weekdayOf(dateStr: string): string {
    const wd = D.parse(dateStr).getDay();
    const names: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    return names[wd] ? names[wd] : '';
  }

  /** yyyy-MM-ddTHH:mm 转成当天分钟数，用于时间轴排序 */
  static minutesOf(s: string): number {
    if (s.length < 16) { return 0; }
    return Number(s.slice(11, 13)) * 60 + Number(s.slice(14, 16));
  }

  /** 简短日期：11-06 */
  static short(s: string): string {
    return s.length >= 10 ? s.slice(5, 10) : s;
  }

  // ---- 以下是重做界面时按工作台文案补的（date-fns 的 format 对应项）----

  /** yyyy.MM.dd（首页 eyebrow 用） */
  static dotDate(d: Date): string {
    return `${d.getFullYear()}.${D.p(d.getMonth() + 1)}.${D.p(d.getDate())}`;
  }

  /** 星期四（date-fns format EEEE + zhCN） */
  static weekdayFull(d: Date): string {
    const names: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    return names[d.getDay()] ? names[d.getDay()] : '';
  }

  /** M月d日（format "M月d日"） */
  static md(s: string | null): string {
    if (!s || s.length < 10) { return ''; }
    return `${Number(s.slice(5, 7))}月${Number(s.slice(8, 10))}日`;
  }

  /** M/d（format "M/d"） */
  static slashMd(d: Date): string {
    return `${d.getMonth() + 1}/${d.getDate()}`;
  }

  /** MM.dd（format "MM.dd"） */
  static dotMd(d: Date): string {
    return `${D.p(d.getMonth() + 1)}.${D.p(d.getDate())}`;
  }

  /** dd（两位数日期） */
  static dd(d: Date): string {
    return D.p(d.getDate());
  }

  /** HH:mm（format "HH:mm"） */
  static hm(s: string | null): string {
    return s && s.length >= 16 ? s.slice(11, 16) : '';
  }

  /** 距离今天的天数差（正数=未来） */
  static diffDays(target: Date, base: Date): number {
    const a = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
    const b = new Date(base.getFullYear(), base.getMonth(), base.getDate()).getTime();
    return Math.round((a - b) / 86400000);
  }

  /** 同一天？ */
  static sameDay(s: string | null, d: Date): boolean {
    if (!s || s.length < 10) { return false; }
    return s.slice(0, 10) === `${d.getFullYear()}-${D.p(d.getMonth() + 1)}-${D.p(d.getDate())}`;
  }

  /** 某天的 yyyy-MM-dd */
  static key(d: Date): string {
    return `${d.getFullYear()}-${D.p(d.getMonth() + 1)}-${D.p(d.getDate())}`;
  }

  /** 从某个基准日期往后推 n 天（返回 Date） */
  static dateAdd(base: Date, n: number): Date {
    const d = new Date(base.getFullYear(), base.getMonth(), base.getDate());
    d.setDate(d.getDate() + n);
    return d;
  }
}
