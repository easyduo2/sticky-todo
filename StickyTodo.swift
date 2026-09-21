import SwiftUI
import AppKit
import UserNotifications
import Carbon.HIToolbox

// MARK: - 数据模型

enum NoteColor: String, CaseIterable, Codable, Identifiable {
    case yellow, pink, blue, green, purple, orange

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.00, green: 0.95, blue: 0.69)
        case .pink:   return Color(red: 1.00, green: 0.84, blue: 0.88)
        case .blue:   return Color(red: 0.82, green: 0.91, blue: 1.00)
        case .green:  return Color(red: 0.84, green: 0.96, blue: 0.83)
        case .purple: return Color(red: 0.90, green: 0.85, blue: 1.00)
        case .orange: return Color(red: 1.00, green: 0.88, blue: 0.76)
        }
    }

    var accent: Color {
        switch self {
        case .yellow: return Color(red: 0.72, green: 0.54, blue: 0.12)
        case .pink:   return Color(red: 0.76, green: 0.33, blue: 0.48)
        case .blue:   return Color(red: 0.18, green: 0.44, blue: 0.69)
        case .green:  return Color(red: 0.24, green: 0.55, blue: 0.24)
        case .purple: return Color(red: 0.42, green: 0.31, blue: 0.69)
        case .orange: return Color(red: 0.77, green: 0.44, blue: 0.16)
        }
    }

    /// V5：深色模式下稍暗的对应色相（保证便签卡片在深色外观下可读）
    var darkColor: Color {
        switch self {
        case .yellow: return Color(red: 0.34, green: 0.29, blue: 0.15)
        case .pink:   return Color(red: 0.38, green: 0.22, blue: 0.29)
        case .blue:   return Color(red: 0.22, green: 0.33, blue: 0.48)
        case .green:  return Color(red: 0.24, green: 0.38, blue: 0.26)
        case .purple: return Color(red: 0.32, green: 0.27, blue: 0.47)
        case .orange: return Color(red: 0.42, green: 0.29, blue: 0.19)
        }
    }

    /// V5：深色模式下更亮的 accent（在暗色卡片背景上保证对比度）
    var accentBright: Color {
        switch self {
        case .yellow: return Color(red: 0.98, green: 0.82, blue: 0.36)
        case .pink:   return Color(red: 1.00, green: 0.62, blue: 0.79)
        case .blue:   return Color(red: 0.55, green: 0.75, blue: 1.00)
        case .green:  return Color(red: 0.54, green: 0.86, blue: 0.55)
        case .purple: return Color(red: 0.78, green: 0.66, blue: 1.00)
        case .orange: return Color(red: 1.00, green: 0.68, blue: 0.38)
        }
    }

    /// V5：按当前外观返回卡片背景色
    func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkColor : color
    }

    /// V5：按当前外观返回 accent（浅色用原 accent，深色用亮化版）
    func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? accentBright : accent
    }

    var displayName: String { rawValue.capitalized }
}

/// 数据变更通知（NoteStore.save() 每次持久化后发出，菜单栏角标据此刷新）
extension Notification.Name {
    static let stickyTodosDidChange = Notification.Name("stickyTodosDidChange")
    /// V2：请求打开全局快速添加小窗（面板内兜底按钮触发）
    static let openQuickAdd = Notification.Name("stickyTodoOpenQuickAdd")
    /// V3：请求打开周报小结弹窗（面板/历史页入口触发）
    static let openWeeklyReport = Notification.Name("stickyTodoOpenWeeklyReport")
}

/// 重复任务规则：#每日 / #每周X / #每月X号
struct RepeatRule: Codable, Equatable {
    enum Kind: String, Codable {
        case daily, weekly, monthly
    }

    var kind: Kind
    /// weekly 专用：1=周一 … 7=周日；「每周末」= [6, 7]
    var weekdays: [Int] = []
    /// monthly 专用：1-31
    var dayOfMonth: Int?

    /// 界面显示文本（历史行 / 胶囊）
    var displayText: String {
        switch kind {
        case .daily:
            return "每日"
        case .weekly:
            if weekdays == [6, 7] { return "每周末" }
            if weekdays.count == 1, let w = weekdays.first {
                return "每周\(Self.weekdayName(w))"
            }
            return "每周" + weekdays.sorted().map { Self.weekdayName($0) }.joined(separator: "/")
        case .monthly:
            return "每月\(dayOfMonth ?? 1)号"
        }
    }

    /// 编辑框重建语法用（# 前缀 + 规则片段）
    var inputText: String {
        switch kind {
        case .daily: return "每日"
        case .weekly:
            if weekdays == [6, 7] { return "每周末" }
            if weekdays.count == 1, let w = weekdays.first {
                return "每周\(Self.weekdayName(w))"
            }
            return "每周" + weekdays.sorted().map { Self.weekdayName($0) }.joined(separator: "、")
        case .monthly:
            return "每月\(dayOfMonth ?? 1)号"
        }
    }

    static func weekdayName(_ w: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][max(0, min(6, w - 1))]
    }
}

struct TodoItem: Identifiable, Codable {
    var id = UUID()
    var text: String
    var done: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?
    /// 定时提醒时间（`#时间` 语法解析后单独存储；nil 表示无提醒）
    var remindAt: Date?
    /// 优先级：0普通 / 1重要 / 2紧急（`!` / `!!` 前缀解析）
    var priority: Int = 0
    /// 重复任务规则（`#每日` / `#每周X` / `#每月X号`；nil 表示一次性）
    var repeatRule: RepeatRule?

    init(id: UUID = UUID(), text: String, done: Bool = false, createdAt: Date = Date(),
         completedAt: Date? = nil, remindAt: Date? = nil,
         priority: Int = 0, repeatRule: RepeatRule? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.remindAt = remindAt
        self.priority = priority
        self.repeatRule = repeatRule
    }

    enum CodingKeys: String, CodingKey {
        case id, text, done, createdAt, completedAt, remindAt, priority, repeatRule
    }

    /// 旧数据兼容：缺失字段（priority/repeatRule）自动回退默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        remindAt = try c.decodeIfPresent(Date.self, forKey: .remindAt)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
    }
}

struct Note: Identifiable, Codable {
    var id = UUID()
    var title: String = ""
    var color: NoteColor = .yellow
    var todos: [TodoItem] = []
    var rotation: Double = Double.random(in: -1.6...1.6)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// V2：便签折叠状态（折叠后仅显示标题行）；持久化到 UserDefaults，兼容旧数据缺失
    var isCollapsed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, color, todos, rotation, createdAt, updatedAt, isCollapsed
    }

    /// 旧数据兼容：isCollapsed 缺失自动回退 false
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        color = try c.decodeIfPresent(NoteColor.self, forKey: .color) ?? .yellow
        todos = try c.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? Double.random(in: -1.6...1.6)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    }

    init(id: UUID = UUID(), title: String = "", color: NoteColor = .yellow,
         todos: [TodoItem] = [], rotation: Double = Double.random(in: -1.6...1.6),
         createdAt: Date = Date(), updatedAt: Date = Date(), isCollapsed: Bool = false) {
        self.id = id
        self.title = title
        self.color = color
        self.todos = todos
        self.rotation = rotation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isCollapsed = isCollapsed
    }
}

// MARK: - 时间工具

enum TimeText {
    /// 相对时间："刚刚 / N分钟前 / 今天 / 昨天 / N天前 / M月d日"
    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let s = Int(Date().timeIntervalSince(date))
            if s < 60 { return "刚刚" }
            let m = s / 60
            if m < 60 { return "\(m) 分钟前" }
            return "今天"
        }
        if cal.isDateInYesterday(date) { return "昨天" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days > 0 && days < 7 { return "\(days) 天前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日"
        return fmt.string(from: date)
    }

    static func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// 提醒徽标显示：今天 → "HH:mm"；今年 → "M月d日 HH:mm"；跨年 → "yyyy-MM-dd HH:mm"
    static func reminderString(_ date: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        if cal.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
        } else if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            fmt.dateFormat = "M月d日 HH:mm"
        } else {
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
        }
        return fmt.string(from: date)
    }
}

// MARK: - 提醒时间解析（# 语法）

enum TimeParser {
    /// 从文本中提取第一个 `#时间`，返回（去掉时间片段的干净文本, 提醒时间）。
    /// 支持：`#14:30`（今天，已过顺延明天）、`#09-22 10:00`（今年月日）、`#2026-09-22 10:00`（完整日期）。
    /// 无匹配返回 nil。
    static func parseReminder(_ text: String) -> (clean: String, date: Date)? {
        let patterns: [(regex: String, build: ([Int]) -> Date?)] = [
            // 完整日期 #2026-09-22 10:00
            (regex: #"#\s*(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})"#,
             build: { c in
                 guard c.count == 5 else { return nil }
                 return date(year: c[0], month: c[1], day: c[2], hour: c[3], minute: c[4])
             }),
            // 月日 #09-22 10:00（今年；已过则明年）
            (regex: #"#\s*(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})"#,
             build: { c in
                 guard c.count == 4 else { return nil }
                 let cal = Calendar.current
                 let year = cal.component(.year, from: Date())
                 if let d = date(year: year, month: c[0], day: c[1], hour: c[2], minute: c[3]) {
                     if d < Date() {
                         return date(year: year + 1, month: c[0], day: c[1], hour: c[2], minute: c[3])
                     }
                     return d
                 }
                 return nil
             }),
            // 当天时间 #14:30（已过则明天）
            (regex: #"#\s*(\d{1,2}):(\d{2})"#,
             build: { c in
                 guard c.count == 2 else { return nil }
                 let cal = Calendar.current
                 var comps = cal.dateComponents([.year, .month, .day], from: Date())
                 comps.hour = c[0]
                 comps.minute = c[1]
                 comps.second = 0
                 if let d = cal.date(from: comps) {
                     if d < Date() {
                         return cal.date(byAdding: .day, value: 1, to: d)
                     }
                     return d
                 }
                 return nil
             })
        ]

        let nsText = text as NSString
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p.regex) else { continue }
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { continue }
            var comps: [Int] = []
            for i in 1..<match.numberOfRanges {
                let r = match.range(at: i)
                guard r.location != NSNotFound else { return nil }
                comps.append(Int(nsText.substring(with: r)) ?? 0)
            }
            guard let d = p.build(comps) else { continue }
            let clean = nsText.replacingCharacters(in: match.range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (clean, d)
        }
        return nil
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps)
    }
}

// MARK: - 重复任务解析（#每日 / #每周X / #每月X号）

enum RepeatParser {
    /// 从文本中提取第一个 `#重复规则`，返回（去掉规则片段的文本, 规则）。无匹配返回 nil。
    static func parse(_ text: String) -> (clean: String, rule: RepeatRule)? {
        let nsText = text as NSString
        let patterns: [(regex: String, build: ([String]) -> RepeatRule?)] = [
            // #每日 / #每天
            (regex: #"#\s*(每日|每天)"#,
             build: { _ in RepeatRule(kind: .daily) }),
            // #每周X（一~日 / 1~7 / 末=周末）
            (regex: #"#\s*每周\s*(一|二|三|四|五|六|日|天|[1-7]|末)"#,
             build: { caps in
                 guard let s = caps.first else { return nil }
                 let map: [String: [Int]] = [
                     "一": [1], "1": [1], "二": [2], "2": [2], "三": [3], "3": [3],
                     "四": [4], "4": [4], "五": [5], "5": [5], "六": [6], "6": [6],
                     "日": [7], "天": [7], "7": [7], "末": [6, 7]
                 ]
                 guard let wd = map[s] else { return nil }
                 return RepeatRule(kind: .weekly, weekdays: wd)
             }),
            // #每月X号
            (regex: #"#\s*每月\s*(\d{1,2})\s*号?"#,
             build: { caps in
                 guard let s = caps.first, let d = Int(s), (1...31).contains(d) else { return nil }
                 return RepeatRule(kind: .monthly, dayOfMonth: d)
             })
        ]

        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p.regex) else { continue }
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { continue }
            var caps: [String] = []
            for i in 1..<match.numberOfRanges {
                let r = match.range(at: i)
                guard r.location != NSNotFound else { break }
                caps.append(nsText.substring(with: r))
            }
            guard let rule = p.build(caps) else { continue }
            let clean = nsText.replacingCharacters(in: match.range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (clean, rule)
        }
        return nil
    }
}

// MARK: - 任务语法综合解析（优先级 + 重复 + 时间提醒）

struct ParsedTask {
    var clean: String
    var remindAt: Date?
    var repeatRule: RepeatRule?
    var priority: Int
}

enum TaskSyntax {
    /// 依次解析：`!!`/`!` 优先级前缀 → `#重复规则` → `#时间`，返回剩余文本与解析结果。
    static func parse(_ text: String) -> ParsedTask {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) 优先级前缀
        var priority = 0
        if clean.hasPrefix("!!") {
            priority = 2
            clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if clean.hasPrefix("!") {
            priority = 1
            clean = String(clean.dropFirst(1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2) 重复规则
        var repeatRule: RepeatRule?
        if let r = RepeatParser.parse(clean) {
            repeatRule = r.rule
            clean = r.clean
        }

        // 3) 时间提醒
        var remindAt: Date?
        if let r = TimeParser.parseReminder(clean) {
            remindAt = r.date
            clean = r.clean
        }

        return ParsedTask(
            clean: clean.trimmingCharacters(in: .whitespacesAndNewlines),
            remindAt: remindAt,
            repeatRule: repeatRule,
            priority: priority
        )
    }

    /// 重复任务完成后生成下一次（日期按规则推进；时间沿用 remindAt 的时刻；无 remindAt 则不提醒）
    static func nextOccurrence(of todo: TodoItem, rule: RepeatRule, after: Date = Date()) -> TodoItem {
        var next = todo
        next.id = UUID()
        next.done = false
        next.completedAt = nil
        next.createdAt = Date()
        if let remindAt = todo.remindAt {
            next.remindAt = nextRepeatDate(from: remindAt, rule: rule, after: after)
        } else {
            next.remindAt = nil
        }
        return next
    }

    /// 把 remindAt 的时刻推进到 after 之后第一个匹配重复规则的日期
    static func nextRepeatDate(from date: Date, rule: RepeatRule, after: Date) -> Date? {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute], from: date)
        var dayBase: Date?

        switch rule.kind {
        case .daily:
            dayBase = cal.date(byAdding: .day, value: 1, to: after)

        case .weekly:
            let target = rule.weekdays.isEmpty ? [1] : rule.weekdays
            var days = 1
            while days <= 14 {
                guard let d = cal.date(byAdding: .day, value: days, to: after) else { break }
                let wd = cal.component(.weekday, from: d)
                let swiftWeekday = wd == 1 ? 7 : wd - 1 // 1=周一 … 7=周日
                if target.contains(swiftWeekday) {
                    dayBase = d
                    break
                }
                days += 1
            }

        case .monthly:
            let day = rule.dayOfMonth ?? 1
            var comps = cal.dateComponents([.year, .month], from: after)
            comps.day = day
            if var d = cal.date(from: comps) {
                if d <= after {
                    guard let nextMonth = cal.date(byAdding: .month, value: 1, to: after) else { return nil }
                    var comps2 = cal.dateComponents([.year, .month], from: nextMonth)
                    comps2.day = day
                    if var d2 = cal.date(from: comps2) {
                        if cal.component(.day, from: d2) != day,
                           let range = cal.range(of: .day, in: .month, for: nextMonth) {
                            comps2.day = range.count
                            d2 = cal.date(from: comps2) ?? d2
                        }
                        d = d2
                    }
                }
                dayBase = d
            } else {
                // 本月无此日（如 31 号）→ 取本月最后一天
                if let range = cal.range(of: .day, in: .month, for: after) {
                    var comps3 = cal.dateComponents([.year, .month], from: after)
                    comps3.day = range.count
                    dayBase = cal.date(from: comps3)
                }
            }
        }

        guard let base = dayBase else { return nil }
        var c = cal.dateComponents([.year, .month, .day], from: base)
        c.hour = time.hour
        c.minute = time.minute
        c.second = 0
        return cal.date(from: c)
    }
}

// MARK: - 数据存储

final class NoteStore: ObservableObject {
    /// 全局共享数据源：菜单栏面板与主窗口实时同步
    static let shared = NoteStore()
    @Published var notes: [Note] = []
    private let key = "sticky-todo-notes-v1"

    init() {
        load()
        if notes.isEmpty {
            // 首次启动给两张示例便签，方便体验
            notes = [
                Note(title: "欢迎使用 👋", color: .yellow, todos: [
                    TodoItem(text: "单击文字可编辑待办"),
                    TodoItem(text: "点击圆圈勾选完成"),
                    TodoItem(text: "悬停卡片可换色 / 删除")
                ]),
                Note(title: "今日计划", color: .blue, todos: [
                    TodoItem(text: "完成菜单栏便签 App"),
                    TodoItem(text: "喝一杯咖啡")
                ])
            ]
            save()
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: key)
        }
        // 每次持久化后同步本地通知（新增/编辑/删除/完成/取消完成均会走到这里）
        ReminderManager.shared.sync(notes: notes)
        // 数据变更 → 通知菜单栏角标刷新
        NotificationCenter.default.post(name: .stickyTodosDidChange, object: nil)
    }

    /// 标记便签「有更新」并持久化
    func touch(_ note: Binding<Note>) {
        note.wrappedValue.updatedAt = Date()
        save()
    }

    @discardableResult
    func addNote() -> Note {
        let colors: [NoteColor] = [.yellow, .pink, .blue, .green, .purple, .orange]
        let note = Note(color: colors.randomElement() ?? .yellow)
        notes.append(note)
        save()
        return note
    }

    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        save()
    }

    /// V3：导入备份后整体替换当前数据。save() 统一完成持久化、重排通知、角标与 UI 刷新
    func replaceAll(with newNotes: [Note]) {
        notes = newNotes
        save()
    }
}

// MARK: - V3 备份（导出 / 导入 JSON）

/// 备份管理器：将 NoteStore 数据序列化为 JSON 文件，或从 JSON 文件恢复并整体替换。
/// 菜单栏 App 为 accessory 模式，弹出 NSSavePanel/NSOpenPanel 前必须先 activate 应用，
/// 并以 runModal 模态方式弹出，保证面板可见可交互。
enum BackupManager {
    /// 导出全部便签数据（含待办/优先级/重复规则/提醒时间/折叠状态/创建更新完成时间）
    static func export(notes: [Note]) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = "sticky-todo-backup-\(df.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: url, options: .atomic)
            showAlert(title: "导出成功", message: "已导出 \(notes.count) 个便签（含全部待办/优先级/重复/提醒/折叠状态）到：\n\(url.path)", style: .informational)
        } catch {
            showAlert(title: "导出失败", message: error.localizedDescription, style: .critical)
        }
    }

    /// 导入备份：NSOpenPanel 选择 JSON，解码为 [Note] 后整体替换并持久化；
    /// 格式不合法时弹窗提示且不改动现有数据。
    static func importBackup(store: NoteStore) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let notes = try decoder.decode([Note].self, from: data)
            store.replaceAll(with: notes)
            showAlert(title: "导入成功", message: "已导入 \(notes.count) 个便签，当前数据已整体替换并持久化。", style: .informational)
        } catch {
            showAlert(title: "导入失败", message: "备份文件格式不合法，现有数据未改动。\n\(error.localizedDescription)", style: .critical)
        }
    }

    private static func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - V3 周报小结

/// 本周（周一~周日，当前自然周）统计数据
struct WeeklyReport {
    let weekStart: Date
    let weekEnd: Date
    let addedCount: Int
    let completedCount: Int
    let completionRate: Int
    let todayTodoCount: Int
    /// 本周每日新增+完成数量（索引 0=周一 … 6=周日，7 格热力）
    let dailyCounts: [(day: Int, count: Int)]
    /// 按便签分组的本周完成事项（组内按完成时间倒序；组间按最新完成时间倒序）
    let completedByNote: [(note: Note, items: [TodoItem])]

    static func compute(notes: [Note], now: Date = Date()) -> WeeklyReport {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1=周日 … 7=周六
        let daysFromMonday = (weekday + 5) % 7          // 周一=0
        let weekStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysFromMonday, to: now)!)
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let weekEndExclusive = cal.date(byAdding: .day, value: 1, to: weekEnd)!

        var added = 0
        var completed = 0
        var daily: [Int: Int] = [:]
        for d in 0..<7 { daily[d] = 0 }
        var completedByNote: [(note: Note, items: [TodoItem])] = []

        for n in notes {
            var noteItems: [TodoItem] = []
            for t in n.todos {
                if t.createdAt >= weekStart && t.createdAt < weekEndExclusive {
                    added += 1
                    let d = cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: t.createdAt)).day ?? 0
                    if (0..<7).contains(d) { daily[d, default: 0] += 1 }
                }
                if t.done, let comp = t.completedAt, comp >= weekStart && comp < weekEndExclusive {
                    completed += 1
                    noteItems.append(t)
                    let d = cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: comp)).day ?? 0
                    if (0..<7).contains(d) { daily[d, default: 0] += 1 }
                }
            }
            if !noteItems.isEmpty {
                noteItems.sort { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                completedByNote.append((note: n, items: noteItems))
            }
        }

        completedByNote.sort { ($0.items.first?.completedAt ?? .distantPast) > ($1.items.first?.completedAt ?? .distantPast) }

        let rate = added > 0 ? Int((Double(completed) / Double(added) * 100).rounded()) : 100
        let todayCount = Self.todayDueCount(notes: notes, cal: cal, now: now)

        return WeeklyReport(
            weekStart: weekStart,
            weekEnd: weekEnd,
            addedCount: added,
            completedCount: completed,
            completionRate: rate,
            todayTodoCount: todayCount,
            dailyCounts: daily.sorted { $0.key < $1.key }.map { (day: $0.key, count: $0.value) },
            completedByNote: completedByNote
        )
    }

    /// 今日待办：今日未完成且（提醒时间 / 重复规则）属于今日（与菜单栏角标口径一致）
    private static func todayDueCount(notes: [Note], cal: Calendar, now: Date) -> Int {
        var count = 0
        for note in notes {
            for t in note.todos where !t.done {
                var dueToday = false
                if let r = t.remindAt, cal.isDateInToday(r) { dueToday = true }
                if let rule = t.repeatRule {
                    switch rule.kind {
                    case .daily:
                        dueToday = true
                    case .weekly:
                        if rule.weekdays.contains(cal.component(.weekday, from: now)) { dueToday = true }
                    case .monthly:
                        if rule.dayOfMonth == cal.component(.day, from: now) { dueToday = true }
                    }
                }
                if dueToday { count += 1 }
            }
        }
        return count
    }

    var dateRangeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日"
        return "\(fmt.string(from: weekStart)) - \(fmt.string(from: weekEnd))"
    }

    /// 一键复制的纯文本周报
    var reportText: String {
        var lines: [String] = []
        lines.append("【便签Todo 本周小结】\(dateRangeText)")
        lines.append("本周完成 \(completedCount) 项，新增 \(addedCount) 项，完成率 \(completionRate)%。")
        if completedByNote.isEmpty {
            lines.append("完成事项：本周暂无完成事项。")
        } else {
            lines.append("完成事项：")
            for group in completedByNote {
                let title = group.note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let noteName = title.isEmpty ? "未命名便签" : title
                for t in group.items {
                    lines.append("- \(t.text)（\(noteName)）")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 胶带装饰

struct TapeView: View {
    // V5：深色模式适配（胶带半透明白在深色下降低亮度避免刺眼）
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.55))
            .frame(width: 72, height: 20)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
            .rotationEffect(.degrees(2.5))
    }
}

// MARK: - 待办行

struct TodoRowView: View {
    @Binding var todo: TodoItem
    let accent: Color
    let onChanged: () -> Void
    let onDelete: () -> Void
    /// 勾选完成且该待办是重复任务时回调（由卡片负责生成下一次待办）
    var onComplete: ((TodoItem) -> Void)?
    /// V2 搜索命中关键词：非空时高亮显示
    var highlight: String = ""

    @State private var editing = false
    @State private var editText = ""
    @State private var hovered = false
    @FocusState private var editFocused: Bool
    // 提醒时间编辑
    @State private var remindEditing = false
    @State private var remindText = ""
    @FocusState private var remindFocused: Bool
    // V5：深色模式适配
    @Environment(\.colorScheme) private var colorScheme

    /// V5：卡片主文字色（浅色模式深棕 / 深色模式近白）
    private var textColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.25, green: 0.22, blue: 0.18)
    }
    /// V5：次要文字 / 图标色
    private var secondaryTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }
    /// V5：输入框底色（浅色半透明白 / 深色半透明白）
    private var inputFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.6)
    }
    /// V5：次要填充（圆点 / 胶囊）
    private var subtleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)
    }

    /// 编辑时实时解析任务语法（#时间 / #重复）：输入即识别，未保存也显示徽标；清除语法后自动消失
    private var liveSyntax: ParsedTask? {
        guard editing, !editText.isEmpty else { return nil }
        let p = TaskSyntax.parse(editText)
        if p.remindAt == nil && p.repeatRule == nil { return nil }
        return p
    }

    // 优先级显示辅助
    private var prioritySymbol: String {
        switch todo.priority {
        case 2: return "!!"
        case 1: return "!"
        default: return "·"
        }
    }
    private var priorityColor: Color {
        switch todo.priority {
        case 2: return .red
        case 1: return .orange
        default: return colorScheme == .dark ? Color.white.opacity(0.40) : Color.black.opacity(0.26)
        }
    }
    private var priorityHelp: String {
        switch todo.priority {
        case 2: return "紧急（点击降为普通）"
        case 1: return "重要（点击升级为紧急）"
        default: return "普通（点击标记为重要）"
        }
    }
    private func cyclePriority() {
        if todo.done { return }
        todo.priority = (todo.priority + 1) % 3
        onChanged()
    }

    /// V2 搜索高亮：把文本中所有命中片段加黄色底
    private func highlighted(_ text: String, term: String) -> AttributedString {
        var result = AttributedString(text)
        let lower = term.lowercased()
        var pos = text.startIndex
        while pos < text.endIndex,
              let r = text.range(of: lower, options: .caseInsensitive, range: pos..<text.endIndex) {
            if let ar = Range(r, in: result) {
                result[ar].backgroundColor = Color.yellow.opacity(0.55)
            }
            pos = r.upperBound
        }
        return result
    }

    var body: some View {
        HStack(spacing: 7) {
            // 勾选完成（记录完成时间；重复任务完成后由卡片生成下一次）
            Button {
                if todo.done {
                    todo.done = false
                    todo.completedAt = nil
                } else {
                    todo.done = true
                    todo.completedAt = Date()
                    if todo.repeatRule != nil {
                        onComplete?(todo)
                    }
                }
                onChanged()
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(todo.done ? accent : (colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .help(todo.done ? "标记为未完成" : "标记为完成")

            // 内容 / 编辑（VStack：任务文本 + 提醒徽标 / 提醒编辑框）
            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    TextField("", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($editFocused)
                        .onSubmit { commit() }
                        .onChange(of: editFocused) { _, focused in
                            if !focused { commit() }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(inputFill)
                        )
                        // 编辑中实时识别 #重复 / #时间 → 立即显示徽标（未保存即可见）
                        if let live = liveSyntax {
                            HStack(spacing: 4) {
                                if let rule = live.repeatRule {
                                    Label(rule.displayText, systemImage: "repeat")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(accent.opacity(0.13)))
                                }
                                if let d = live.remindAt {
                                    Label("将在 \(TimeText.reminderString(d)) 提醒", systemImage: "clock")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(accent.opacity(0.13)))
                                }
                            }
                            .padding(.top, 1)
                        }
                } else {
                    HStack(spacing: 4) {
                        // 优先级标记（点击循环切换 普通→重要→紧急→普通）
                        Button {
                            cyclePriority()
                        } label: {
                            Text(prioritySymbol)
                                .font(.system(size: 11, weight: todo.priority == 2 ? .heavy : .bold))
                                .foregroundColor(priorityColor)
                                .frame(width: 16)
                        }
                        .buttonStyle(.plain)
                        .help(priorityHelp)

                        if !highlight.isEmpty {
                            Text(highlighted(todo.text, term: highlight))
                                .font(.system(size: 13))
                                .foregroundColor(todo.done ? .secondary : textColor)
                                .strikethrough(todo.done, color: .secondary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    startEdit()
                                }
                        } else {
                            Text(todo.text)
                                .font(.system(size: 13))
                                .foregroundColor(todo.done ? .secondary : textColor)
                                .strikethrough(todo.done, color: .secondary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    startEdit()
                                }
                        }
                    }
                }

                // 提醒徽标 / 提醒编辑框
                if remindEditing {
                    HStack(spacing: 4) {
                        TextField("如 14:30 或 #09-22 10:00", text: $remindText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .focused($remindFocused)
                            .onSubmit { commitReminder() }
                            .onChange(of: remindFocused) { _, focused in
                                if !focused { commitReminder() }
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(inputFill)
                            )
                        Button { commitReminder() } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(accent)
                        }
                        .buttonStyle(.plain)
                        .help("确认提醒时间")
                        Button { clearReminder() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(secondaryTint)
                        }
                        .buttonStyle(.plain)
                        .help("清除提醒")
                    }
                    .padding(.vertical, 1)
                } else if let remindAt = todo.remindAt, !todo.done {
                    Button {
                        startRemindEdit()
                    } label: {
                        Label(TimeText.reminderString(remindAt), systemImage: "clock")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(accent.opacity(0.13)))
                    }
                    .buttonStyle(.plain)
                    .help("点击编辑提醒时间（重新输入 # 时间）")
                }

                // 重复任务徽标（非编辑态常驻显示）
                if let rule = todo.repeatRule {
                    Label(rule.displayText, systemImage: "repeat")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(accent.opacity(todo.done ? 0.4 : 0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(accent.opacity(0.13)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 悬停操作
            if hovered && !editing && !remindEditing {
                HStack(spacing: 0) {
                    Button { startEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("编辑")

                    Button { onDelete() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
                .foregroundColor(secondaryTint)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 3)
        .background(hovered ? subtleFill : .clear)
        .cornerRadius(4)
        .onHover { h in hovered = h }
    }

    private func startEdit() {
        editing = true
        // 重建语法前缀：优先级（!! / !）+ 重复规则（#每日 等），编辑提交时再解析回字段
        let p = todo.priority == 2 ? "!! " : (todo.priority == 1 ? "! " : "")
        let r = todo.repeatRule.map { "#\($0.inputText) " } ?? ""
        editText = p + r + todo.text
        DispatchQueue.main.async {
            editFocused = true
        }
    }

    private func commit() {
        guard editing else { return }
        let v = editText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 仅输入 "#" → 进入提醒时间编辑
        if v == "#" {
            editing = false
            DispatchQueue.main.async {
                self.remindEditing = true
                self.remindText = self.todo.remindAt.map { TimeText.reminderString($0) } ?? ""
                self.remindFocused = true
            }
            return
        }

        // 综合解析：优先级前缀 + #重复规则 + #时间
        let parsed = TaskSyntax.parse(v)
        if let r = parsed.remindAt {
            todo.remindAt = r
            // V4：提醒时间修改后重置已发超时标记，新时间过期后可重新追加提醒
            ReminderManager.shared.resetOverdueMark(for: todo.id)
        }
        // 重复规则：编辑框已重建规则前缀，删除 #规则 即清除（与 #时间 保留语义不同）
        todo.repeatRule = parsed.repeatRule
        // 编辑文本即修改优先级：无前缀 → 普通
        todo.priority = parsed.priority
        if !parsed.clean.isEmpty {
            todo.text = parsed.clean
        } else if parsed.remindAt == nil && parsed.repeatRule == nil && !v.isEmpty {
            // 无任何语法且文本非空
            todo.text = v
        }
        // 整行都是语法（如 "#每天" / "#14:30"）→ 仅设置字段，保留原任务文本
        editing = false
        onChanged()
    }

    /// 点击徽标进入提醒编辑
    private func startRemindEdit() {
        remindText = todo.remindAt.map { TimeText.reminderString($0) } ?? ""
        remindEditing = true
        DispatchQueue.main.async {
            self.remindFocused = true
        }
    }

    /// 提交提醒时间（支持直接输入 14:30 或 # 语法；空内容 = 清除）
    private func commitReminder() {
        guard remindEditing else { return }
        let v = remindText.trimmingCharacters(in: .whitespacesAndNewlines)
        remindEditing = false
        if v.isEmpty {
            clearReminder()
            return
        }
        let src = v.hasPrefix("#") ? v : "#\(v)"
        if let r = TimeParser.parseReminder(src) {
            todo.remindAt = r.date
            onChanged()
        }
        // 解析失败：保持原提醒不变
    }

    /// 清除提醒时间
    private func clearReminder() {
        guard todo.remindAt != nil else { remindEditing = false; return }
        todo.remindAt = nil
        // V4：清除提醒后重置已发超时标记（sync 会移除该任务的 -overdue pending）
        ReminderManager.shared.resetOverdueMark(for: todo.id)
        onChanged()
    }
}

// MARK: - 便签卡片

struct NoteCardView: View {
    @Binding var note: Note
    @ObservedObject var store: NoteStore
    let focusTitle: Bool
    /// V2 面板内搜索关键词（从 ContentView 传入）
    var searchText: String = ""

    @State private var hovered = false
    @State private var newTodoText = ""
    @FocusState private var titleFocused: Bool
    // V5：深色模式适配
    @Environment(\.colorScheme) private var colorScheme

    /// V5：按外观取卡片背景 / accent / 主文字 / 次要文字 / 分割线 / 细描边 / 次要填充
    private var effectiveBackground: Color { note.color.color(for: colorScheme) }
    private var effectiveAccent: Color { note.color.accent(for: colorScheme) }
    private var effectiveText: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.29, green: 0.25, blue: 0.21)
    }
    private var effectiveSecondary: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }
    private var effectiveDivider: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
    }
    private var effectiveHairline: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.05)
    }
    private var effectiveSubtleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)
    }

    /// 添加待办输入时实时解析任务语法（#重复 / #时间）：输入即识别，未提交也显示徽标；清除语法后自动消失
    private var liveAddSyntax: ParsedTask? {
        guard !newTodoText.isEmpty else { return nil }
        let p = TaskSyntax.parse(newTodoText)
        if p.remindAt == nil && p.repeatRule == nil { return nil }
        return p
    }

    /// 待办显示排序：优先级降序（紧急 > 重要 > 普通），同级保持原有顺序
    private var sortedTodoIndices: [Int] {
        note.todos.indices.sorted { i, j in
            let a = note.todos[i], b = note.todos[j]
            if a.priority != b.priority { return a.priority > b.priority }
            return i < j
        }
    }

    /// V2 搜索状态
    private var searchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var titleMatched: Bool {
        searchActive && note.title.localizedCaseInsensitiveContains(searchText)
    }

    /// V2 搜索过滤后的待办索引：未搜索 → 全部；标题命中 → 全部；否则只保留文本命中的待办
    private var displayTodoIndices: [Int] {
        let sorted = sortedTodoIndices
        guard searchActive else { return sorted }
        if titleMatched { return sorted }
        return sorted.filter { note.todos[$0].text.localizedCaseInsensitiveContains(searchText) }
    }

    /// 添加输入框下方实时语法徽标（#重复 / #时间）
    private var addSyntaxCapsules: some View {
        HStack(spacing: 4) {
            if let live = liveAddSyntax {
                if let rule = live.repeatRule {
                    Label(rule.displayText, systemImage: "repeat")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(effectiveAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(effectiveAccent.opacity(0.13)))
                }
                if let d = live.remindAt {
                    Label("将在 \(TimeText.reminderString(d)) 提醒", systemImage: "clock")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(effectiveAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(effectiveAccent.opacity(0.13)))
                }
            }
        }
    }

    /// 重复任务完成 → 按规则生成下一次待办
    private func spawnNextIfRepeat(_ completed: TodoItem) {
        guard let rule = completed.repeatRule else { return }
        let next = TaskSyntax.nextOccurrence(of: completed, rule: rule)
        withAnimation(.easeOut(duration: 0.15)) {
            note.todos.append(next)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 卡片主体
            cardContent
            // 胶带
            TapeView()
                .offset(y: -13)
            // 颜色选择器（悬停显示）
            if hovered {
                colorPicker
            }
        }
        .rotationEffect(.degrees(hovered ? 0 : note.rotation))
        .scaleEffect(hovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovered)
        .onHover { h in hovered = h }
        .onAppear {
            if focusTitle {
                DispatchQueue.main.async { titleFocused = true }
            }
        }
    }

    /// 卡片主体（标题 + 待办列表 + 新增输入 + 底部）；折叠后仅显示标题行
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleField
            if !note.isCollapsed {
                todoList
                if !searchActive {
                    addRow
                }
                footer
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 26)
        .padding(.bottom, 6)
        .frame(width: 250, height: note.isCollapsed ? 68 : 290)
        .background(effectiveBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(effectiveHairline, lineWidth: 0.5)
        )
    }

    private var titleField: some View {
        HStack(spacing: 6) {
            TextField("", text: $note.title)
                .font(.system(size: 16, weight: .bold))
                .textFieldStyle(.plain)
                .foregroundColor(effectiveText)
                .lineLimit(1)
                .truncationMode(.tail)
                .focused($titleFocused)
                .onChange(of: note.title) { store.touch($note) }
                // V5：标题为空显示占位文字「未命名便签」
                .overlay(alignment: .leading) {
                    if note.title.isEmpty {
                        Text("未命名便签")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(effectiveSecondary.opacity(0.65))
                            .allowsHitTesting(false)
                    }
                }

            // V2 折叠 / 展开按钮
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    note.isCollapsed.toggle()
                }
                store.touch($note)
            } label: {
                Image(systemName: note.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(effectiveSecondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(effectiveSubtleFill))
            }
            .buttonStyle(.plain)
            .help(note.isCollapsed ? "展开便签" : "折叠便签")
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(effectiveDivider).frame(height: 1)
        }
    }

    private var todoList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if note.todos.isEmpty {
                    Text("暂无待办，添加一条吧")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                ForEach(displayTodoIndices, id: \.self) { idx in
                    TodoRowView(
                        todo: $note.todos[idx],
                        accent: effectiveAccent,
                        onChanged: { store.touch($note) },
                        onDelete: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                let tid = note.todos[idx].id
                                note.todos.removeAll { $0.id == tid }
                            }
                            store.touch($note)
                        },
                        onComplete: { completed in
                            spawnNextIfRepeat(completed)
                        },
                        highlight: searchActive && !titleMatched ? searchText : ""
                    )
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                TextField("添加待办，回车确认…", text: $newTodoText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit { addTodo() }
                Button { addTodo() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(effectiveAccent))
                }
                .buttonStyle(.plain)
                .help("添加待办")
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(effectiveDivider).frame(height: 1)
            }
            .padding(.top, 8)
            // 添加待办实时识别 #重复 / #时间 → 未提交即显示徽标（与编辑态一致）
            addSyntaxCapsules
                .padding(.top, 3)
        }
    }

    private var footer: some View {
        HStack {
            Text("更新于 \(TimeText.relative(note.updatedAt))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            if hovered {
                Button {
                    store.deleteNote(note)
                } label: {
                    Label("删除便签", systemImage: "trash")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(effectiveSubtleFill))
                }
                .buttonStyle(.plain)
                .help("删除整张便签")
                .transition(.opacity)
            }
        }
        .frame(height: 26)
    }

    private var colorPicker: some View {
        HStack(spacing: 5) {
            ForEach(NoteColor.allCases) { c in
                Circle()
                    .fill(c.color(for: colorScheme))
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle().stroke(pickerStroke(for: c, selected: c == note.color), lineWidth: 1.2)
                    )
                    .onTapGesture {
                        note.color = c
                        store.touch($note)
                    }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.88)))
        .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
        .offset(y: -8)
        .transition(.opacity)
    }

    /// V5：颜色选择器描边（拆分辅助方法，避免类型检查超时）
    private func pickerStroke(for c: NoteColor, selected: Bool) -> Color {
        if colorScheme == .dark {
            return selected ? Color.white.opacity(0.75) : Color.white.opacity(0.30)
        }
        return selected ? Color.black.opacity(0.55) : Color.black.opacity(0.15)
    }

    private func addTodo() {
        let v = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        let parsed = TaskSyntax.parse(v)
        var item = TodoItem(text: parsed.clean.isEmpty ? v : parsed.clean)
        // 综合语法：优先级前缀 / #重复规则 / #时间
        item.priority = parsed.priority
        item.repeatRule = parsed.repeatRule
        item.remindAt = parsed.remindAt
        withAnimation(.easeOut(duration: 0.15)) {
            note.todos.append(item)
        }
        newTodoText = ""
        store.touch($note)
    }
}

// MARK: - 时间线热图（GitHub 风格，近 180 天）

struct HeatmapView: View {
    @ObservedObject var store: NoteStore
    // V5：深色模式适配（热图边框/面板底色）
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered: (date: Date, count: Int)?

    private let totalDays = 180
    private var columns: Int { (totalDays + 6) / 7 } // 26 列

    private var startDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: -(totalDays - 1), to: today)!
    }

    /// 按自然日聚合「新增 + 完成」数量
    private var counts: [Date: Int] {
        var dict: [Date: Int] = [:]
        let cal = Calendar.current
        for n in store.notes {
            for t in n.todos {
                dict[cal.startOfDay(for: t.createdAt), default: 0] += 1
                if let comp = t.completedAt {
                    dict[cal.startOfDay(for: comp), default: 0] += 1
                }
            }
        }
        return dict
    }

    private func dayColor(_ count: Int) -> Color {
        if colorScheme == .dark {
            switch count {
            case 0: return Color(red: 0.28, green: 0.28, blue: 0.27)
            case 1: return Color(red: 0.30, green: 0.55, blue: 0.33)
            case 2: return Color(red: 0.38, green: 0.72, blue: 0.38)
            case 3: return Color(red: 0.46, green: 0.86, blue: 0.42)
            default: return Color(red: 0.60, green: 0.98, blue: 0.48)
            }
        }
        switch count {
        case 0: return Color(red: 0.90, green: 0.90, blue: 0.88)
        case 1: return Color(red: 0.80, green: 0.90, blue: 0.72)
        case 2: return Color(red: 0.55, green: 0.78, blue: 0.45)
        case 3: return Color(red: 0.33, green: 0.62, blue: 0.28)
        default: return Color(red: 0.20, green: 0.46, blue: 0.16)
        }
    }

    /// V5：热图格子边框色（浅色黑 / 深色白）
    private var heatStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
    }
    /// V5：热图面板底色（浅色半透明白 / 深色半透明白低亮）
    private var panelFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.5)
    }

    private var hoverText: String {
        guard let h = hovered else { return "悬停格子查看每日数量" }
        return "\(TimeText.dateString(h.date)) · \(h.count) 项"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("时间线热图", systemImage: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("近 \(totalDays) 天 · 新增 + 完成")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // 悬停信息行
            Text(hoverText)
                .font(.system(size: 10.5))
                .foregroundColor(hovered == nil ? .secondary : .primary)
                .frame(height: 14, alignment: .leading)

            // 格子矩阵：列 = 周，行 = 周日…周六
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<columns, id: \.self) { col in
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { row in
                            let offset = col * 7 + row
                            if offset < totalDays {
                                let date = Calendar.current.date(byAdding: .day, value: offset, to: startDate)!
                                let count = counts[date] ?? 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(dayColor(count))
                                    .frame(width: 11, height: 11)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(heatStroke, lineWidth: 0.5)
                                    )
                                    .onHover { h in
                                        if h {
                                            hovered = (date, count)
                                        } else if hovered?.date == date {
                                            hovered = nil
                                        }
                                    }
                            } else {
                                Color.clear.frame(width: 11, height: 11)
                            }
                        }
                    }
                }
            }

            // 图例
            HStack(spacing: 5) {
                Text("少").font(.system(size: 9)).foregroundColor(.secondary)
                ForEach([0, 1, 2, 3, 4], id: \.self) { c in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dayColor(c))
                        .frame(width: 10, height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(heatStroke, lineWidth: 0.5)
                        )
                }
                Text("多").font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(panelFill))
    }
}

// MARK: - 历史视图

struct HistoryView: View {
    @ObservedObject var store: NoteStore
    // V5：深色模式适配
    @Environment(\.colorScheme) private var colorScheme

    /// V5：周报入口强调色（浅色蓝紫 / 深色亮蓝紫）
    private var historyTint: Color {
        colorScheme == .dark
            ? Color(red: 0.62, green: 0.70, blue: 0.95)
            : Color(red: 0.35, green: 0.42, blue: 0.62)
    }
    /// 已完成待办（按完成时间倒序）
    private var completedItems: [(note: Note, todo: TodoItem)] {
        var items: [(Note, TodoItem)] = []
        for n in store.notes {
            for t in n.todos where t.done {
                items.append((n, t))
            }
        }
        return items.sorted { ($0.1.completedAt ?? .distantPast) > ($1.1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HeatmapView(store: store)

            HStack {
                Text("已完成历史")
                    .font(.system(size: 12, weight: .semibold))
                Text("(\(completedItems.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                // V3：周报小结入口（本周统计 + 一键复制）
                Button {
                    NotificationCenter.default.post(name: .openWeeklyReport, object: nil)
                } label: {
                    Label("周报小结", systemImage: "calendar.badge.checkmark")
                        .font(.system(size: 10.5))
                        .foregroundColor(historyTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(historyTint.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("查看本周统计并复制周报文本")
                if !completedItems.isEmpty {
                    Button {
                        clearHistory()
                    } label: {
                        Label("清空历史", systemImage: "trash")
                            .font(.system(size: 10.5))
                            .foregroundColor(.red.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("从所有便签中移除全部已完成待办")
                }
            }
            .padding(.horizontal, 4)

            if completedItems.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("暂无已完成事项")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(completedItems, id: \.todo.id) { item in
                            HistoryRow(
                                note: item.note,
                                todo: item.todo,
                                onRestore: { restore(item) },
                                onRemove: { remove(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restore(_ item: (note: Note, todo: TodoItem)) {
        guard let ni = store.notes.firstIndex(where: { $0.id == item.note.id }),
              let ti = store.notes[ni].todos.firstIndex(where: { $0.id == item.todo.id }) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            store.notes[ni].todos[ti].done = false
            store.notes[ni].todos[ti].completedAt = nil
            store.notes[ni].updatedAt = Date()
        }
        store.save()
    }

    private func remove(_ item: (note: Note, todo: TodoItem)) {
        guard let ni = store.notes.firstIndex(where: { $0.id == item.note.id }) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            store.notes[ni].todos.removeAll { $0.id == item.todo.id }
            store.notes[ni].updatedAt = Date()
        }
        store.save()
    }

    private func clearHistory() {
        withAnimation(.easeOut(duration: 0.15)) {
            for i in store.notes.indices {
                let before = store.notes[i].todos.count
                store.notes[i].todos.removeAll { $0.done }
                if store.notes[i].todos.count != before {
                    store.notes[i].updatedAt = Date()
                }
            }
        }
        store.save()
    }
}

struct HistoryRow: View {
    let note: Note
    let todo: TodoItem
    let onRestore: () -> Void
    let onRemove: () -> Void

    @State private var hovered = false
    // V5：深色模式适配
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            // 所属便签色块
            RoundedRectangle(cornerRadius: 3)
                .fill(note.color.color(for: colorScheme))
                .frame(width: 26, height: 26)
                .overlay(
                    Text(note.title.isEmpty ? "签" : String(note.title.prefix(1)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    // 历史中保留优先级与重复标记
                    if todo.priority > 0 {
                        Text(todo.priority == 2 ? "!!" : "!")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(todo.priority == 2 ? .red : .orange)
                    }
                    Text(todo.text)
                        .font(.system(size: 12.5))
                        .strikethrough()
                        .lineLimit(1)
                    if let rule = todo.repeatRule {
                        Label(rule.displayText, systemImage: "repeat")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(note.color.accent(for: colorScheme).opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(note.color.accent(for: colorScheme).opacity(0.12)))
                    }
                }
                Text("完成于 \(TimeText.relative(todo.completedAt ?? Date()))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if hovered {
                Button {
                    onRestore()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("恢复为未完成")

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("删除该历史记录")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(
            colorScheme == .dark
                ? (hovered ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                : (hovered ? Color.white.opacity(0.55) : Color.white.opacity(0.25))
        ))
        .onHover { h in hovered = h }
    }
}

// MARK: - 主界面（便签面板 / 主窗口共用）

struct ContentView: View {
    /// 共享数据源：面板与窗口实时同步
    @ObservedObject private var store: NoteStore
    /// 仅窗口模式显示「返回菜单栏」按钮；面板模式传 nil
    let onOpenWindow: (() -> Void)?
    /// 仅菜单栏面板模式显示「打开主窗口」按钮；窗口模式传 nil
    let onOpenMainWindow: (() -> Void)?

    init(store: NoteStore = .shared, onOpenWindow: (() -> Void)? = nil, onOpenMainWindow: (() -> Void)? = nil) {
        self.store = store
        self.onOpenWindow = onOpenWindow
        self.onOpenMainWindow = onOpenMainWindow
    }

    @State private var focusNoteID: UUID?
    @State private var tab = 0
    /// V2 面板内搜索关键词
    @State private var searchText = ""
    // V5：深色模式适配
    @Environment(\.colorScheme) private var colorScheme

    /// V5：搜索栏面板色（浅色半透明白 / 深色半透明白低亮）
    private var searchPanelFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.55)
    }
    /// V5：搜索栏描边色
    private var searchPanelStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }
    /// V5：主窗口/打开主窗口强调色（浅色蓝紫 / 深色亮蓝紫）
    private var mainTint: Color {
        colorScheme == .dark
            ? Color(red: 0.62, green: 0.70, blue: 0.95)
            : Color(red: 0.35, green: 0.42, blue: 0.62)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 30)
    ]

    /// 「今日优先」排序：今日有活动的便签在前，其余按最近更新倒序；今日活跃的便签再按最高待办优先级（紧急>重要>普通）作为次级排序
    private var sortedIndices: [Int] {
        let cal = Calendar.current
        func isActiveToday(_ n: Note) -> Bool {
            if cal.isDateInToday(n.createdAt) || cal.isDateInToday(n.updatedAt) { return true }
            return n.todos.contains { t in
                cal.isDateInToday(t.createdAt) || (t.completedAt.map { cal.isDateInToday($0) } ?? false)
            }
        }
        func maxPriority(_ n: Note) -> Int {
            n.todos.filter { !$0.done }.map { $0.priority }.max() ?? 0
        }
        return store.notes.indices.sorted { i, j in
            let a = store.notes[i], b = store.notes[j]
            let at = isActiveToday(a), bt = isActiveToday(b)
            if at != bt { return at }
            if at && bt {
                let ap = maxPriority(a), bp = maxPriority(b)
                if ap != bp { return ap > bp }
            }
            return a.updatedAt > b.updatedAt
        }
    }

    /// V2 搜索过滤：仅保留标题或任一待办文本命中的便签；空关键词返回全部
    private var filteredIndices: [Int] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sortedIndices }
        return sortedIndices.filter { idx in
            let n = store.notes[idx]
            if n.title.localizedCaseInsensitiveContains(q) { return true }
            return n.todos.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    /// V2 搜索框 + 快速添加兜底按钮
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            TextField("搜索待办（标题 / 文本，清空恢复）", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
            Button {
                NotificationCenter.default.post(name: .openQuickAdd, object: nil)
            } label: {
                Label("快速添加", systemImage: "plus.circle")
                    .font(.system(size: 11))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .help("全局快速添加（Cmd+Shift+N，可在任意应用呼出）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(searchPanelFill))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(searchPanelStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 44)
        .padding(.bottom, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：便签 / 历史分段 + （窗口模式）返回菜单栏
            HStack(spacing: 12) {
                Picker("", selection: $tab) {
                    Text("便签").tag(0)
                    Text("历史").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                // V3/V4：备份（导出/导入 JSON）、周报小结、通知声音开关入口
                Menu {
                    Button("导出备份…") {
                        BackupManager.export(notes: store.notes)
                    }
                    Button("导入备份…") {
                        BackupManager.importBackup(store: store)
                    }
                    Divider()
                    Button("周报小结…") {
                        NotificationCenter.default.post(name: .openWeeklyReport, object: nil)
                    }
                    Divider()
                    // V4：通知声音开关（持久化；变更后重同步提醒通知使已注册通知生效）
                    Toggle("通知声音", isOn: Binding(
                        get: { ReminderManager.shared.soundEnabled },
                        set: { v in
                            ReminderManager.shared.soundEnabled = v
                            ReminderManager.shared.sync(notes: NoteStore.shared.notes)
                        }
                    ))
                    .toggleStyle(.switch)
                } label: {
                    Label("工具", systemImage: "ellipsis.circle")
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("备份（导出/导入 JSON）、周报小结与通知声音")

                if let onOpenWindow = onOpenWindow {
                    Button(action: onOpenWindow) {
                        Label("返回菜单栏", systemImage: "menubar.rectangle")
                            .font(.system(size: 11.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .help("收起主窗口，回到纯菜单栏模式")
                } else if let onOpenMainWindow = onOpenMainWindow {
                    Button(action: onOpenMainWindow) {
                        Label("打开主窗口", systemImage: "macwindow")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(mainTint)
                    .help("打开独立主窗口（Cmd+Shift+S）")
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            if tab == 0 {
                VStack(spacing: 0) {
                    searchBar
                    notesGrid
                }
            } else {
                HistoryView(store: store)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(
            Group {
                if colorScheme == .dark {
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(red: 0.10, green: 0.10, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.94, blue: 0.90),
                            Color(red: 0.93, green: 0.91, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()
        )
    }

    private var notesGrid: some View {
        ScrollView {
            if filteredIndices.isEmpty && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("没有匹配的待办")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
            }
            // V5：无便签空状态引导
            if store.notes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("还没有便签")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.8))
                    Text("点击下方「新建便签」，或按 Cmd+Shift+N 全局快速添加")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .padding(.bottom, 8)
            }
            LazyVGrid(columns: columns, alignment: .center, spacing: 34) {
                ForEach(filteredIndices, id: \.self) { idx in
                    NoteCardView(
                        note: $store.notes[idx],
                        store: store,
                        focusTitle: focusNoteID == store.notes[idx].id,
                        searchText: searchText
                    )
                }

                // 新建便签
                Button {
                    let n = store.addNote()
                    focusNoteID = n.id
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 38, weight: .light))
                        Text("新建便签")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(
                        colorScheme == .dark ? Color(red: 0.72, green: 0.68, blue: 0.62) : Color(red: 0.62, green: 0.58, blue: 0.52)
                    )
                    .frame(width: 250, height: 290)
                    .background(
                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.28)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                colorScheme == .dark ? Color.white.opacity(0.22) : Color(red: 0.76, green: 0.72, blue: 0.66),
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(44)
        }
    }
}

// MARK: - 菜单栏

/// 鼠标悬停跟踪器（NSTrackingArea owner）
final class HoverTracker: NSResponder {
    private let onEnter: () -> Void
    private let onExit: () -> Void

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

final class StatusItemController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hoverTracker: HoverTracker!
    private var hoverShown = false
    private var hoverWorkItem: DispatchWorkItem?
    /// 角标：5 分钟定时刷新 + 数据变更即时刷新
    private var badgeTimer: Timer?
    private var badgeObserver: NSObjectProtocol?

    /// 供 AppDelegate 在 Dock 点击时收起面板
    var onRequestClosePopover: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "便签 TodoList")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "便签 TodoList（左键便签面板，右键打开主窗口）"

        // 注意：不设置 button.menu，避免与 action/sendAction 冲突导致点击行为异常；
        // 右键菜单在 handleClick 中通过 NSMenu.popUpContextMenu 手动弹出。

        // 悬停跟踪：高亮 + 延迟自动弹出面板（延迟给右键留出时机，避免抢事件）
        hoverTracker = HoverTracker(
            onEnter: { [weak self, weak button] in
                guard let self = self else { return }
                button?.isHighlighted = true
                self.hoverShown = true
                self.scheduleHoverPopover()
            },
            onExit: { [weak self, weak button] in
                button?.isHighlighted = false
                self?.hoverWorkItem?.cancel()
            }
        )
        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: hoverTracker,
            userInfo: nil
        )
        button.addTrackingArea(area)

        // 弹出面板（菜单栏模式）
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView(onOpenMainWindow: { [weak self] in
                self?.openMainWindow()
            })
        )
        popover.contentSize = NSSize(width: 720, height: 560)

        // 本地快捷键：Cmd+Shift+S 打开主窗口（菜单栏面板激活时可用）
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.modifierFlags.intersection([.command, .shift]) == [.command, .shift],
               event.charactersIgnoringModifiers?.lowercased() == "s" {
                self.openMainWindow()
                return nil
            }
            return event
        }

        // 今日角标：立即刷新 + 每 5 分钟刷新 + 数据变更即时刷新
        refreshBadge()
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshBadge()
        }
        badgeObserver = NotificationCenter.default.addObserver(
            forName: .stickyTodosDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshBadge()
        }
    }

    deinit {
        badgeTimer?.invalidate()
        if let o = badgeObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    /// 今日角标：统计今日未完成且（提醒时间 / 重复规则）属于今日的待办数量；无则清空
    private func refreshBadge() {
        guard let button = statusItem.button else { return }
        let count = todayDueCount(notes: NoteStore.shared.notes)
        if count > 0 {
            button.attributedTitle = NSAttributedString(
                string: " \(count)",
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold)
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func todayDueCount(notes: [Note]) -> Int {
        let cal = Calendar.current
        let now = Date()
        var count = 0
        for note in notes {
            for t in note.todos where !t.done {
                var dueToday = false
                if let r = t.remindAt, cal.isDateInToday(r) { dueToday = true }
                if let rule = t.repeatRule {
                    switch rule.kind {
                    case .daily:
                        dueToday = true
                    case .weekly:
                        if rule.weekdays.contains(cal.component(.weekday, from: now)) { dueToday = true }
                    case .monthly:
                        if rule.dayOfMonth == cal.component(.day, from: now) { dueToday = true }
                    }
                }
                if dueToday { count += 1 }
            }
        }
        return count
    }

    private func scheduleHoverPopover() {
        hoverWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.hoverShown { self.showPopover() }
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// 左键：切换面板；右键：手动弹出「打开主窗口 / 退出」菜单
    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            if popover.isShown { popover.performClose(nil) }
            showContextMenu()
            return
        }
        togglePopover()
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 StickyTodo", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            button.menu = menu
            button.performClick(nil)
            button.menu = nil
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async {
            self.popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// 打开独立主窗口（由右键菜单 / 面板内按钮 / 快捷键 / Dock 点击触发）
    @objc func openMainWindow() {
        FileHandle.standardError.write("STICKY_DEBUG openMainWindow(status) called\n".data(using: .utf8)!)
        FileHandle.standardError.write("STICKY_DEBUG stack: \(Thread.callStackSymbols.prefix(8).joined(separator: " | "))\n".data(using: .utf8)!)
        closePopover()
        AppDelegate.current?.openMainWindow()
    }
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// V2 快速添加兜底：菜单栏右键菜单入口
    @objc private func showQuickAdd() {
        if popover.isShown { popover.performClose(nil) }
        NotificationCenter.default.post(name: .openQuickAdd, object: nil)
    }

    // MARK: NSPopoverDelegate
    func popoverShouldClose(_ popover: NSPopover) -> Bool { true }

    func popoverDidClose(_ notification: Notification) {
        hoverShown = false
    }
}

// MARK: - V2 全局快速添加（Cmd+Shift+N）

/// 基于 Carbon RegisterEventHotKey 的全局快捷键（菜单栏 App 无 Dock 时依然可用）
final class GlobalHotKey {
    static let shared = GlobalHotKey()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    @discardableResult
    func register(_ handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler

        // 安装键盘事件处理器（回调不捕获，经 userData 取回 self）
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return noErr }
                let hk = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hk.handler?() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        // Cmd+Shift+N
        var hotKeyID = EventHotKeyID(signature: OSType(0x53544F44), id: 1)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return regStatus == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        handler = nil
    }
}

/// 快速添加小窗（NSPanel，浮于所有应用之上）
final class QuickAddController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: QuickAddView(onDone: { [weak self] in
                    self?.close()
                })
            )
            let win = NSPanel(contentViewController: hosting)
            win.title = "快速添加待办"
            win.styleMask = [.titled, .closable]
            win.level = .floating
            win.isFloatingPanel = true
            win.hidesOnDeactivate = false
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.setContentSize(NSSize(width: 380, height: 118))
            window = win
        }
        guard let win = window else { return }
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}

/// 快速添加输入视图：支持全部语法（! / !!、#时间、#每日 / #每周X / #每月X号），回车添加到最近使用的便签
struct QuickAddView: View {
    let onDone: () -> Void
    @ObservedObject private var store = NoteStore.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    private var liveSyntax: ParsedTask? {
        guard !text.isEmpty else { return nil }
        let p = TaskSyntax.parse(text)
        if p.remindAt == nil && p.repeatRule == nil && p.priority == 0 { return nil }
        return p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("快速添加：!重要 / !!紧急 / #14:30 / #每日…", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { add() }

            HStack(spacing: 6) {
                if let live = liveSyntax {
                    if live.priority == 2 {
                        Label("紧急", systemImage: "exclamationmark.2")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red)
                    } else if live.priority == 1 {
                        Label("重要", systemImage: "exclamationmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    if let rule = live.repeatRule {
                        Label(rule.displayText, systemImage: "repeat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    if let d = live.remindAt {
                        Label("将在 \(TimeText.reminderString(d)) 提醒", systemImage: "clock")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text("回车添加 · Esc 关闭")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(height: 16)
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
        .onExitCommand { onDone() }
    }

    private func add() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        let parsed = TaskSyntax.parse(v)
        var item = TodoItem(text: parsed.clean.isEmpty ? v : parsed.clean)
        item.priority = parsed.priority
        item.repeatRule = parsed.repeatRule
        item.remindAt = parsed.remindAt
        let store = NoteStore.shared
        if store.notes.isEmpty {
            store.addNote()
        }
        // 默认便签：最近使用的便签（updatedAt 最新）
        if let idx = store.notes.indices.max(by: { store.notes[$0].updatedAt < store.notes[$1].updatedAt }) {
            store.notes[idx].todos.append(item)
            store.notes[idx].updatedAt = Date()
        }
        store.save()
        text = ""
        onDone()
    }
}

// MARK: - V3 周报小结弹窗

/// 周报小结弹窗（NSPanel，仿快速添加小窗；accessory 模式下需 activate 应用）
final class WeeklyReportController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: WeeklyReportView(onClose: { [weak self] in
                    self?.close()
                })
            )
            let win = NSPanel(contentViewController: hosting)
            win.title = "周报小结"
            win.styleMask = [.titled, .closable]
            win.level = .floating
            win.isFloatingPanel = true
            win.hidesOnDeactivate = false
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.setContentSize(NSSize(width: 470, height: 600))
            window = win
        }
        guard let win = window else { return }
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}

/// 周报小结视图：本周统计卡片 + 本周热力 + 按便签分组的完成事项 + 一键复制
struct WeeklyReportView: View {
    let onClose: () -> Void
    @ObservedObject private var store = NoteStore.shared
    @State private var copied = false
    // V5：深色模式适配
    @Environment(\.colorScheme) private var colorScheme

    /// V5：统计/热力卡片底色（浅色半透明白 / 深色半透明白低亮）
    private var reportCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.5)
    }
    /// V5：分组小卡底色
    private var reportSubCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.35)
    }
    /// V5：周报强调色（浅色蓝紫 / 深色亮蓝紫）
    private var reportTint: Color {
        colorScheme == .dark
            ? Color(red: 0.62, green: 0.70, blue: 0.95)
            : Color(red: 0.35, green: 0.42, blue: 0.62)
    }
    /// V5：统计数字色
    private var statNumberColor: Color {
        colorScheme == .dark
            ? Color(red: 0.70, green: 0.76, blue: 0.96)
            : Color(red: 0.30, green: 0.36, blue: 0.52)
    }

    private var report: WeeklyReport {
        WeeklyReport.compute(notes: store.notes)
    }

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 + 日期范围
            HStack {
                Label("本周小结", systemImage: "calendar.badge.checkmark")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(report.dateRangeText)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            // 统计卡片：本周新增 / 本周完成 / 完成率 / 今日待办
            HStack(spacing: 8) {
                statCard(title: "本周新增", value: "\(report.addedCount)")
                statCard(title: "本周完成", value: "\(report.completedCount)")
                statCard(title: "完成率", value: "\(report.completionRate)%")
                statCard(title: "今日待办", value: "\(report.todayTodoCount)")
            }

            // 本周热力（周一~周日，每日新增 + 完成）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("本周热力")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("每日新增 + 完成")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { d in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(heatColor(report.dailyCounts[d].count))
                                .frame(width: 34, height: 26)
                            Text("周\(weekdays[d])")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(reportCardFill))

            // 完成事项（按便签分组）
            Text("本周完成事项（按便签分组）")
                .font(.system(size: 12, weight: .semibold))
            if report.completedByNote.isEmpty {
                Text("本周暂无完成事项，继续加油")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(report.completedByNote.indices, id: \.self) { gi in
                            let group = report.completedByNote[gi]
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(group.note.color.color(for: colorScheme))
                                        .frame(width: 14, height: 14)
                                    Text(group.note.title.isEmpty ? "未命名便签" : group.note.title)
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text("(\(group.items.count))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                ForEach(group.items) { t in
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                        Text(t.text)
                                            .font(.system(size: 11.5))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(reportSubCardFill))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Spacer(minLength: 0)

            // 底部操作：复制周报文本 / 关闭
            HStack {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(report.reportText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制到剪贴板" : "复制周报文本", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(reportTint)
                Spacer()
                Button("关闭") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 470)
        .background(
            Group {
                if colorScheme == .dark {
                    LinearGradient(
                        colors: [Color(nsColor: .windowBackgroundColor), Color(red: 0.11, green: 0.11, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.97, green: 0.95, blue: 0.92), Color(red: 0.93, green: 0.92, blue: 0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        )
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(statNumberColor)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(reportCardFill))
    }

    private func heatColor(_ count: Int) -> Color {
        switch count {
        case 0: return colorScheme == .dark
                ? Color(red: 0.24, green: 0.24, blue: 0.26)
                : Color(red: 0.90, green: 0.90, blue: 0.88)
        case 1: return Color(red: 0.80, green: 0.90, blue: 0.72)
        case 2: return Color(red: 0.55, green: 0.78, blue: 0.45)
        case 3: return Color(red: 0.33, green: 0.62, blue: 0.28)
        default: return Color(red: 0.20, green: 0.46, blue: 0.16)
        }
    }
}

// MARK: - 本地通知（定时提醒）

/// 为设置了提醒时间的未完成待办注册本地通知（开始前 15 分钟 + 开始时），
/// 并支持通知内「稍后提醒」action、超时未完成追加提醒、通知声音开关。
/// 通知 id：
/// - reminder-<待办UUID>-15 / reminder-<待办UUID>-0：开始前 15 分钟 / 开始
/// - reminder-<待办UUID>-snooze：稍后提醒（5 分钟 / 1 小时，保留原 remindAt）
/// - reminder-<待办UUID>-overdue：remindAt 后 30 分钟的超时追加提醒（仅一次）
final class ReminderManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderManager()
    private let appName = "便签Todo"
    /// V4：已发超时通知的任务 id 集合（防重复；任务完成/删除时清理）
    private let overdueSentKey = "sticky-todo-overdue-sent"
    /// V4：通知声音开关持久化 key（默认开启）
    private let soundEnabledKey = "sticky-todo-sound-enabled"
    private var overdueSent: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: overdueSentKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: overdueSentKey) }
    }
    /// V4：通知声音开关（关闭时所有通知不携带 sound 字段）
    var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundEnabledKey) }
    }
    private override init() { super.init() }

    /// 启动时调用：注册通知分类（稍后提醒 action）、设置 delegate、申请权限
    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // V4：REMINDER 分类：通知横幅上的「稍后 5 分钟 / 稍后 1 小时」action
        let snooze5 = UNNotificationAction(identifier: "SNOOZE_5", title: "稍后 5 分钟", options: [])
        let snooze60 = UNNotificationAction(identifier: "SNOOZE_60", title: "稍后 1 小时", options: [])
        let category = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [snooze5, snooze60],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    self.sync(notes: NoteStore.shared.notes)
                }
            }
        }
    }

    /// 全量同步：按当前数据增量维护通知。
    /// - 移除：已完成/已删除任务残留的 reminder 通知（-15/-0/-overdue/-snooze）
    /// - 保留：仍存在未完成任务对应的 -15/-0/-overdue 与 -snooze（避免编辑其他便签时误删）
    /// - 注册：当前未完成待办的 -15/-0；超时未完成的 -overdue（仅一次）
    func sync(notes: [Note]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self = self else { return }
            var keepBase = Set<String>()
            var keepSnooze = Set<String>()
            for note in notes {
                for todo in note.todos where !todo.done {
                    keepSnooze.insert(todo.id.uuidString)
                    guard todo.remindAt != nil else { continue }
                    keepBase.insert("reminder-\(todo.id.uuidString)-15")
                    keepBase.insert("reminder-\(todo.id.uuidString)-0")
                    keepBase.insert("reminder-\(todo.id.uuidString)-overdue")
                }
            }
            let remove = requests.map { $0.identifier }.filter { id in
                guard id.hasPrefix("reminder-") else { return false }
                if id.hasSuffix("-snooze") {
                    let uuid = String(id.dropFirst("reminder-".count).dropLast("-snooze".count))
                    return !keepSnooze.contains(uuid)
                }
                return !keepBase.contains(id)
            }
            if !remove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: remove)
            }
            // 重新注册基础提醒（同 id 重复 add 会覆盖旧请求）
            for note in notes {
                for todo in note.todos where !todo.done {
                    self.register(todo: todo)
                }
            }
            // V4：超时未完成追加提醒扫描
            self.scanOverdue(notes: notes)
        }
    }

    private func register(todo: TodoItem) {
        guard let remindAt = todo.remindAt else { return }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: remindAt)
        comps.second = 0
        guard let fireAt = cal.date(from: comps) else { return }
        let minutesUntil = fireAt.timeIntervalSince(Date()) / 60.0
        guard minutesUntil > 0 else { return } // 已过时间不注册

        let center = UNUserNotificationCenter.current()
        let baseID = "reminder-\(todo.id.uuidString)"

        // 距离开始 > 15 分钟：注册「开始前 15 分钟」通知
        if minutesUntil > 15 {
            let content15 = self.makeContent(
                body: "任务 15 分钟后开始：\(todo.text)",
                taskID: todo.id,
                type: "reminder"
            )
            let req15 = UNNotificationRequest(
                identifier: "\(baseID)-15",
                content: content15,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            center.add(req15)
        }

        // 开始通知（15 分钟内只发这一条）
        let content0 = self.makeContent(
            body: "任务开始：\(todo.text)",
            taskID: todo.id,
            type: "reminder"
        )
        let req0 = UNNotificationRequest(
            identifier: "\(baseID)-0",
            content: content0,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        center.add(req0)
    }

    // MARK: V4 通知内容统一构造（REMINDER 分类 + taskID/type + 声音开关）

    private func makeContent(body: String, taskID: UUID, type: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = appName
        content.body = body
        content.categoryIdentifier = "REMINDER"
        content.userInfo = ["taskID": taskID.uuidString, "type": type]
        if soundEnabled {
            content.sound = .default
        }
        return content
    }

    // MARK: V4 超时未完成追加提醒

    /// 扫描未完成且 remindAt 已过、且未发过超时通知的任务，注册 reminder-<uuid>-overdue（仅一次）。
    /// 同时清理已发集合中已完成/已删除任务的标记（完成/删除自动移除）。
    private func scanOverdue(notes: [Note]) {
        var currentIDs = Set<String>()
        for note in notes {
            for todo in note.todos where !todo.done && todo.remindAt != nil {
                currentIDs.insert(todo.id.uuidString)
            }
        }
        let cleaned = overdueSent.intersection(currentIDs)
        if cleaned != overdueSent {
            overdueSent = cleaned
        }
        let now = Date()
        for note in notes {
            for todo in note.todos where !todo.done {
                guard let r = todo.remindAt, r < now else { continue }
                guard !overdueSent.contains(todo.id.uuidString) else { continue }
                registerOverdue(todo: todo)
            }
        }
    }

    /// 注册一条超时追加提醒：remindAt 后 30 分钟触发；若已过触发点则 1 秒后立即送达（仍仅一次）。
    private func registerOverdue(todo: TodoItem) {
        guard let remindAt = todo.remindAt else { return }
        let fireAt = remindAt.addingTimeInterval(30 * 60)
        let center = UNUserNotificationCenter.current()
        let content = makeContent(body: "任务已超时：\(todo.text)", taskID: todo.id, type: "overdue")
        let trigger: UNNotificationTrigger
        if fireAt > Date() {
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
            comps.second = 0
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        let req = UNNotificationRequest(
            identifier: "reminder-\(todo.id.uuidString)-overdue",
            content: content,
            trigger: trigger
        )
        center.add(req)
        var set = overdueSent
        set.insert(todo.id.uuidString)
        overdueSent = set
    }

    /// V4：提醒时间被修改后重置该任务的已发超时标记（新 remindAt 过期后可重新追加提醒）
    func resetOverdueMark(for taskID: UUID) {
        var set = overdueSent
        if set.remove(taskID.uuidString) != nil {
            overdueSent = set
        }
    }

    // MARK: V4 稍后提醒

    /// 通知内「稍后 5 分钟 / 稍后 1 小时」action 回调：按所选延迟重新调度一条该任务的提醒通知
    /// （保留原任务 remindAt 不变，仅延迟发一条重复提醒，id = reminder-<uuid>-snooze）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let content = response.notification.request.content
        guard let taskIDStr = content.userInfo["taskID"] as? String,
              let taskID = UUID(uuidString: taskIDStr) else { return }
        let delay: TimeInterval
        switch response.actionIdentifier {
        case "SNOOZE_5": delay = 5 * 60
        case "SNOOZE_60": delay = 60 * 60
        default: return // 点按通知主体等不做处理
        }
        // 从当前数据取任务文本；已删除任务不重发
        var text = "任务"
        outer: for note in NoteStore.shared.notes {
            for t in note.todos where t.id == taskID {
                text = t.text
                break outer
            }
        }
        let content2 = makeContent(body: "任务提醒：\(text)", taskID: taskID, type: "snooze")
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let req = UNNotificationRequest(
            identifier: "reminder-\(taskID.uuidString)-snooze",
            content: content2,
            trigger: trigger
        )
        center.add(req)
    }

    // MARK: UNUserNotificationCenterDelegate
    /// App 前台时也展示横幅通知（声音按开关）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - App 入口（菜单栏模式 + 窗口模式并存）

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 真实 AppDelegate 实例引用：SwiftUI 的 @NSApplicationDelegateAdaptor 会让 NSApp.delegate
    /// 指向 SwiftUI 内部包装对象（SwiftUI.AppDelegate），不能依赖 (NSApp.delegate as? AppDelegate)；
    /// 在 applicationDidFinishLaunching 中记录 self，供 StatusItemController 等调用。
    static var current: AppDelegate?
    private var statusItemController: StatusItemController?
    private var mainWindowController: MainWindowController?
    private var quickAddController: QuickAddController?
    private var weeklyReportController: WeeklyReportController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.current = self
        FileHandle.standardError.write("STICKY_DEBUG didFinishLaunching, self=\(String(describing: self))\n".data(using: .utf8)!)
        NSApp.setActivationPolicy(.accessory) // 默认纯菜单栏模式（隐藏 Dock）
        let controller = StatusItemController()
        controller.setup()
        statusItemController = controller
        // V2：全局快速添加小窗（快捷键 + 面板/菜单兜底通知）
        quickAddController = QuickAddController()
        // V3：周报小结弹窗
        weeklyReportController = WeeklyReportController()
        let hkOK = GlobalHotKey.shared.register { [weak self] in
            self?.showQuickAdd()
        }
        FileHandle.standardError.write("STICKY_DEBUG globalHotKey registered=\(hkOK)\n".data(using: .utf8)!)
        // 申请通知权限并在授权后重新注册全部提醒（重启恢复）
        ReminderManager.shared.setup()

        // 主窗口关闭 → 切回 accessory（纯菜单栏模式）；面板窗口关闭不触发
        let noteCenter = NotificationCenter.default
        observers.append(noteCenter.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let closed = note.object as? NSWindow,
                  closed === self.mainWindowController?.window else { return }
            FileHandle.standardError.write("STICKY_DEBUG main window willClose\n".data(using: .utf8)!)
            self.mainWindowController?.window = nil
            self.mainWindowController = nil
            NSApp.setActivationPolicy(.accessory)
        })
        observers.append(noteCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 激活时若主窗口已打开，关闭菜单栏面板避免遮挡
            self?.statusItemController?.closePopover()
        })
        // V2：面板内「快速添加」按钮兜底入口
        observers.append(noteCenter.addObserver(
            forName: .openQuickAdd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showQuickAdd()
        })
        // V3：面板/历史页「周报小结」按钮兜底入口
        observers.append(noteCenter.addObserver(
            forName: .openWeeklyReport,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.weeklyReportController?.show()
        })
    }

    /// V2：唤起全局快速添加小窗
    func showQuickAdd() {
        quickAddController?.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if mainWindowController?.window == nil {
            openMainWindow()
        } else if let window = mainWindowController?.window {
            // V5：窗口位置恢复校验——窗口已关闭或不在任何可见屏幕内时重新居中，避免丢失/错位
            if window.screen == nil || !(window.screen?.visibleFrame.intersects(window.frame) ?? false) {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    /// 打开 / 聚焦主窗口（右键菜单、Dock 点击、窗口内按钮共用）
    func openMainWindow() {
        NSLog("STICKY_DEBUG openMainWindow(appDelegate) called")
        if mainWindowController?.window != nil {
            NSLog("STICKY_DEBUG openMainWindow(appDelegate) window exists, show")
            if let window = mainWindowController?.window {
                // V5：窗口位置恢复校验——窗口已关闭或不在任何可见屏幕内时重新居中，避免丢失/错位
                if window.screen == nil || !(window.screen?.visibleFrame.intersects(window.frame) ?? false) {
                    window.center()
                }
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        NSLog("STICKY_DEBUG openMainWindow(appDelegate) creating")
        NSApp.setActivationPolicy(.regular) // 显示 Dock 图标
        let controller = MainWindowController()
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        mainWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        let _w = mainWindowController?.window
        FileHandle.standardError.write("STICKY_DEBUG post-open win=\(String(describing: _w)) visible=\(_w?.isVisible ?? false) policy=\(NSApp.activationPolicy().rawValue) screen=\(String(describing: _w?.screen))\n".data(using: .utf8)!)
        NSLog("STICKY_DEBUG openMainWindow(appDelegate) done")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// 独立主窗口控制器（窗口模式）
final class MainWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    override init() {
        super.init()
        let hosting = NSHostingController(rootView: ContentView(onOpenWindow: { [weak self] in
            self?.closeToMenuBar()
        }))
        let win = NSWindow(contentViewController: hosting)
        win.title = "StickyTodo"
        win.setContentSize(NSSize(width: 900, height: 700))
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.collectionBehavior = [.fullScreenPrimary]
        win.delegate = self
        win.center()
        window = win
    }

    /// 「返回菜单栏」：关闭主窗口并隐藏 Dock（触发 willClose 通知 → accessory）
    private func closeToMenuBar() {
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}

@main
struct StickyTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
