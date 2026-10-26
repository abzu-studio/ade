import Foundation

public let attendanceFormula = "present / (present + absent)"
public let databaseFormat = "ade-db-v1"
public let syncFormat = "ade-sync-v1"
public let backupFormat = "ade-backup-v1"

public enum VolunteerWeights {
    public static let completed = 10
    public static let recentCompleted = 5
    public static let sameComponentCompleted = 2
    public static let selected = 3
    public static let priorInterested = 1
    public static let interestedNow = 8
    public static let declined = -2
    public static let absent = -4
    public static let attendancePresent = 1
    public static let attendancePresentCap = 10
    public static let recentDays = 180
}

public struct PagePoints: Equatable {
    public var width: Double
    public var height: Double
}

public enum PageMetrics {
    public static let letter = PagePoints(width: 612, height: 792)
    public static let a4 = PagePoints(width: 595.28, height: 841.89)

    public static func size(_ page: PageSize) -> PagePoints {
        page == .letter ? letter : a4
    }
}

public let eventTransitions: [EventStatus: [EventStatus]] = [
    .draft: [.scheduled, .cancelled],
    .scheduled: [.draft, .completed, .cancelled],
    .completed: [.scheduled, .cancelled],
    .cancelled: [.scheduled],
]

public let volunteerTransitions: [VolunteerState: [VolunteerState]] = [
    .interested: [.selected, .declined],
    .selected: [.completed, .declined, .absent, .interested],
    .completed: [.selected],
    .declined: [.interested],
    .absent: [.selected],
]

public func consumesVolunteerCapacity(_ state: VolunteerState) -> Bool {
    state == .selected || state == .completed
}

public enum CoreErrorCode: String, Equatable {
    case NAME_REQUIRED
    case INVALID_DATE
    case INVALID_DATE_RANGE
    case NOT_FOUND
    case OVERLAPPING_MEMBERSHIP
    case CAPACITY_EXCEEDED
    case INVALID_CAPACITY
    case DUPLICATE_PARTICIPANT
    case CATEGORY_COMPONENT_MISMATCH
    case INVALID_TRANSITION
    case ATTENDANCE_NOT_ALLOWED
    case VOLUNTEER_NOT_ALLOWED
    case PERSON_NOT_PARTICIPANT
    case IN_USE
    case INVALID_TEMPLATE
    case INVALID_IMPORT
    case NOTHING_TO_UNDO
    case NOTHING_TO_REDO
    case ASSET_IN_USE
    case ASSET_NOT_FOUND
    case EVENT_LOCKED
}

public struct CoreError: Equatable {
    public var code: CoreErrorCode
    public var params: [String: String]
    public init(_ code: CoreErrorCode, _ params: [String: String] = [:]) {
        self.code = code
        self.params = params
    }
}

public enum CoreResult<T> {
    case ok(T)
    case err(CoreError)

    public var isOk: Bool {
        if case .ok = self { return true }
        return false
    }

    public var value: T? {
        if case .ok(let value) = self { return value }
        return nil
    }

    public var error: CoreError? {
        if case .err(let error) = self { return error }
        return nil
    }
}

public func ok<T>(_ value: T) -> CoreResult<T> { .ok(value) }
public func err<T>(_ code: CoreErrorCode, _ params: [String: String] = [:]) -> CoreResult<T> {
    .err(CoreError(code, params))
}

private let isoDatePattern = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})$"#)
private let isoDateTimePattern = try! NSRegularExpression(
    pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#
)

public func isIsoDate(_ value: String) -> Bool {
    let range = NSRange(value.startIndex..., in: value)
    guard let match = isoDatePattern.firstMatch(in: value, range: range), match.numberOfRanges == 4 else {
        return false
    }
    func part(_ index: Int) -> Int? {
        guard let slice = Range(match.range(at: index), in: value) else { return nil }
        return Int(value[slice])
    }
    guard let year = part(1), let month = part(2), let day = part(3) else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    guard let date = calendar.date(from: components) else { return false }
    let back = calendar.dateComponents([.year, .month, .day], from: date)
    return back.year == year && back.month == month && back.day == day
}

public func isIsoDateTime(_ value: String) -> Bool {
    if value.isEmpty { return false }
    let range = NSRange(value.startIndex..., in: value)
    return isoDateTimePattern.firstMatch(in: value, range: range) != nil
}

public func dateInRange(_ date: String, start: String, end: String?) -> Bool {
    if date < start { return false }
    if let end, date > end { return false }
    return true
}

public func rangesOverlap(aStart: String, aEnd: String?, bStart: String, bEnd: String?) -> Bool {
    let aStop = aEnd ?? "9999-12-31"
    let bStop = bEnd ?? "9999-12-31"
    return aStart <= bStop && bStart <= aStop
}

public func daysBetween(_ earlier: String, _ later: String) -> Int {
    func utc(_ value: String) -> TimeInterval {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        return date.timeIntervalSince1970
    }
    return Int(((utc(later) - utc(earlier)) / 86_400).rounded())
}

public func isoTimestamp(_ date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, locale: Foundation.Locale(identifier: "en"))
}

func isBefore(_ lhs: String, _ rhs: String) -> Bool {
    compareText(lhs, rhs) == .orderedAscending
}
