// entry/src/main/ets/db/LocalAI.ets
// 离线「AI」：不联网也能用的中文小助手。
// 两件事：
//   1) parse()  —— 把一段碎碎念拆成任务（规则式：分句 + 关键词判断领域 / 紧急度 / 日期）
//   2) review() —— 按本地数据起一篇复盘草稿（今天/这周做成了什么、卡在哪、明天做什么）
// v4.0 之前这两件事是调云端大模型；现在 App 完全离线，所以改成纯本地规则。
import { AiDraft, Area, Priority, Task, Note, Review } from '../api/Types';
import { D } from '../utils/DateUtil';

interface AreaRule {
  area: string;
  words: string[];
}

const AREA_RULES: AreaRule[] = [
  {
    area: 'media',
    words: ['小红书', '抖音', 'B站', 'b站', '视频号', '视频', '选题', '剪辑', '公众号', '文案',
      '发布', '涨粉', '直播', '快手', '视频号', '对标账号', '账号']
  },
  {
    area: 'side',
    words: ['副业', '接单', '外包', '私活', '变现', '兼职', '赚', '报价单', '渠道', '客户开发']
  },
  {
    area: 'study',
    words: ['学习', '看书', '读书', '课程', '论文', '背单词', '英语', '复习', '考试', '刷题',
      '网课', '教程', '练习', '笔记整理']
  },
  {
    area: 'life',
    words: ['健身', '跑步', '买菜', '家人', '睡觉', '吃饭', '医院', '体检', '打扫', '遛狗',
      '宠物', '旅行', '洗澡', '理发', '买菜', '房租', '水电']
  },
  {
    area: 'work',
    words: ['客户', '会议', '周会', '方案', '需求', '上线', '汇报', 'PPT', '合同', '报价',
      '对接', '项目', '开发', '修复', 'bug', '代码', '联调', '评审', '排期', '部署', '服务器']
  }
];

const HIGH_WORDS: string[] = ['紧急', '很急', '急', '要紧', '马上', '立刻', '必须', '别忘',
  '尽快', 'deadline', '截止', '今天必须'];
const LOW_WORDS: string[] = ['不急', '随缘', '有空', '闲了', '选做', '可做可不做', '以后再说'];

const WEEK_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];

export class LocalAI {
  // ───────────────────────── 拆任务 ─────────────────────────

  /**
   * 把一段话拆成任务。规则式：先分句，再逐句判断领域 / 优先级 / 日期。
   * 最多 8 条，标题不超过 24 个字。
   */
  static parse(text: string): AiDraft[] {
    const out: AiDraft[] = [];
    const raw: string = (text ?? '').trim();
    if (raw.length === 0) { return out; }

    const parts: string[] = raw.split(/[\n\r;；。!！?？]+/);
    for (const part of parts) {
      const seg: string = part.trim();
      if (seg.length < 2) { continue; }
      const title: string = LocalAI.cleanTitle(seg);
      if (title.length < 2) { continue; }
      const due: string | null = LocalAI.detectDate(seg);
      const draft: AiDraft = {
        title: LocalAI.cut(title, 24),
        area: LocalAI.detectArea(seg) as Area,
        priority: LocalAI.detectPriority(seg) as Priority,
        due_date: due
      };
      out.push(draft);
      if (out.length >= 8) { break; }
    }
    return out;
  }

  /** 去掉开头的项目符号、序号，和结尾的标点 */
  private static cleanTitle(s: string): string {
    let t: string = s.trim();
    t = t.replace(/^[-•·*·]+/, '');
    t = t.replace(/^\d+[.、)）]\s*/, '');
    t = t.replace(/^[（(]\s*[0-9]+\s*[)）]\s*/, '');
    t = t.replace(/[，,。.、；;！!？?~～\s]+$/, '');
    t = t.trim();
    // 把「在 X 月 X 日」这类日期短语挪走后留下的空壳也一并收拾
    t = t.replace(/^(要|得|需要|记得|计划|准备)\s*/, '');
    return t.trim();
  }

  private static cut(s: string, n: number): string {
    return s.length > n ? s.substring(0, n) : s;
  }

  /** 判断领域：命中关键词最多的那个 */
  private static detectArea(s: string): string {
    let best: string = 'work';
    let bestHits: number = 0;
    for (const rule of AREA_RULES) {
      let hits: number = 0;
      for (const w of rule.words) {
        if (s.indexOf(w) >= 0) { hits += 1; }
      }
      if (hits > bestHits) {
        bestHits = hits;
        best = rule.area;
      }
    }
    return best;
  }

  /** 判断紧急度 */
  private static detectPriority(s: string): string {
    for (const w of HIGH_WORDS) {
      if (s.indexOf(w) >= 0) { return 'high'; }
    }
    for (const w of LOW_WORDS) {
      if (s.indexOf(w) >= 0) { return 'low'; }
    }
    return 'med';
  }

  /**
   * 识别日期。命中就返回 yyyy-MM-dd，没命中返回 null（不瞎编日期）。
   * 支持：今天 / 明天 / 后天 / 大后天 / 昨天 / 前天 /
   *       周一…周日 / 星期X / 下周X /
   *       X月X日 / X/X / X-X / yyyy-MM-dd
   */
  static detectDate(s: string): string | null {
    const today: string = D.today();

    if (s.indexOf('大后天') >= 0) { return D.addDays(today, 3); }
    if (s.indexOf('后天') >= 0) { return D.addDays(today, 2); }
    if (s.indexOf('明天') >= 0 || s.indexOf('明早') >= 0 || s.indexOf('明晚') >= 0) {
      return D.addDays(today, 1);
    }
    if (s.indexOf('今天') >= 0 || s.indexOf('今晚') >= 0 || s.indexOf('今早') >= 0) { return today; }
    if (s.indexOf('昨天') >= 0) { return D.addDays(today, -1); }
    if (s.indexOf('前天') >= 0) { return D.addDays(today, -2); }

    // 下周X / 本周X / 周X / 星期X
    const nextWeek: boolean = s.indexOf('下周') >= 0;
    for (let i = 0; i < WEEK_NAMES.length; i++) {
      const name: string = WEEK_NAMES[i];
      const hit: boolean = s.indexOf(`周${name}`) >= 0 || s.indexOf(`星期${name}`) >= 0
        || s.indexOf(`礼拜${name}`) >= 0;
      if (!hit) { continue; }
      // 0=周日 … 6=周六；下周要落到下一个自然周
      let offset: number = i === 0 ? 6 : i - 1;
      const todayIdx: number = LocalAI.weekdayIndex(today);
      let delta: number = offset - todayIdx;
      if (delta <= 0) { delta += 7; }
      if (nextWeek && delta < 7) { delta += 7; }
      return D.addDays(today, delta);
    }

    // yyyy-MM-dd / yyyy/MM/dd
    const iso: RegExp = /(\d{4})[-/](\d{1,2})[-/](\d{1,2})/;
    const isoHit: RegExpMatchArray | null = s.match(iso);
    if (isoHit !== null && isoHit.length >= 4) {
      return `${isoHit[1]}-${D.p(Number(isoHit[2]))}-${D.p(Number(isoHit[3]))}`;
    }

    // X月X日
    const md: RegExp = /(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]/;
    const mdHit: RegExpMatchArray | null = s.match(md);
    if (mdHit !== null && mdHit.length >= 3) {
      const year: number = new Date().getFullYear();
      return `${year}-${D.p(Number(mdHit[1]))}-${D.p(Number(mdHit[2]))}`;
    }

    // X/X 或 X-X（本年度）
    const slash: RegExp = /(\d{1,2})[-/](\d{1,2})(?!\d)/;
    const slashHit: RegExpMatchArray | null = s.match(slash);
    if (slashHit !== null && slashHit.length >= 3) {
      const mo: number = Number(slashHit[1]);
      const da: number = Number(slashHit[2]);
      if (mo >= 1 && mo <= 12 && da >= 1 && da <= 31) {
        const year: number = new Date().getFullYear();
        return `${year}-${D.p(mo)}-${D.p(da)}`;
      }
    }
    return null;
  }

  /** 星期几 → 0(周日)…6(周六) */
  private static weekdayIndex(dateStr: string): number {
    return D.parse(dateStr).getDay();
  }

  // ───────────────────────── 起复盘草稿 ─────────────────────────

  /**
   * 按本地数据起一篇复盘草稿。
   * daily 看当天，weekly 看本周一~周日。全部离线，不调任何服务。
   */
  static review(date: string, type: string, tasks: Task[], notes: Note[], reviews: Review[]): ReviewDraft {
    const from: string = type === 'weekly' ? D.weekStart() : date;
    const to: string = type === 'weekly' ? D.addDays(D.weekStart(), 6) : date;
    const today: string = D.today();

    const done: string[] = [];
    const stuck: string[] = [];
    const nextUp: string[] = [];

    for (const t of tasks) {
      const due: string = t.due_date ?? '';
      const doneDay: string = t.done_at ? t.done_at.substring(0, 10) : '';
      const inRange: boolean = due.length > 0 && due >= from && due <= to;

      if (t.status === 'done' && doneDay.length > 0 && doneDay >= from && doneDay <= to) {
        done.push(t.title);
        continue;
      }
      if (t.status !== 'done' && due.length > 0 && due < today && (inRange || due >= D.addDays(from, -14))) {
        stuck.push(t.title);
        continue;
      }
      if (t.status !== 'done') {
        // v4.4：① 没写到期日的任务也要算候选（以前永远轮不上）；
        //        ② 候选要按到期日排序（没到期日的排最后）。
        const inWindow: boolean = inRange || (due.length > 0 && due > to && due <= D.addDays(to, 3));
        if (inWindow || due.length === 0) {
          nextUp.push(`${due.length > 0 ? due : '9999-12-31'}\u0001${t.title}`);
        }
      }
    }
    // v4.4：按到期日升序排（没到期日的排在最后）
    for (let i = 0; i < nextUp.length; i++) {
      for (let j = i + 1; j < nextUp.length; j++) {
        if (nextUp[j] < nextUp[i]) {
          const tmp: string = nextUp[i];
          nextUp[i] = nextUp[j];
          nextUp[j] = tmp;
        }
      }
    }
    for (let i = 0; i < nextUp.length; i++) {
      const cut: number = nextUp[i].indexOf('\u0001');
      nextUp[i] = nextUp[i].substring(cut + 1);
    }

    const noteCount: number = LocalAI.countNotes(notes, from, to);
    const did: string = done.length > 0
      ? `做完了 ${done.length} 件事：${LocalAI.clip(done, 3)}。`
      : (type === 'weekly' ? '这周还没有标记完成的任务。' : '今天还没有标记完成的任务。');
    const stuckText: string = stuck.length > 0
      ? `卡在 ${stuck.length} 件上：${LocalAI.clip(stuck, 3)}。`
      : '暂时没有明显卡住的地方。';
    const tomorrow: string = nextUp.length > 0
      ? `先把「${nextUp[0]}」做完。`
      : '还没定下最重要的一件事，明天先挑一件小事做完。';

    const hint: string = noteCount > 0
      ? `（这段时间还记了 ${noteCount} 条灵感，可以翻翻记录找找细节。）`
      : '';

    const draft: ReviewDraft = {
      did: did + hint,
      stuck: stuckText,
      tomorrow: tomorrow
    };
    return draft;
  }

  private static countNotes(notes: Note[], from: string, to: string): number {
    let n: number = 0;
    for (const x of notes) {
      const day: string = x.created_at.substring(0, 10);
      if (day >= from && day <= to) { n += 1; }
    }
    return n;
  }

  /** 取前 n 条拼成一句话 */
  private static clip(list: string[], n: number): string {
    if (list.length <= n) { return list.join('、'); }
    return `${list.slice(0, n).join('、')} 等 ${list.length} 件`;
  }
}

export interface ReviewDraft {
  did: string;
  stuck: string;
  tomorrow: string;
}
