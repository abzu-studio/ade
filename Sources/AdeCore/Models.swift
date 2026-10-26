import Foundation

@propertyWrapper
public struct Nullable<Value: Codable & Equatable>: Codable, Equatable {
    public var wrappedValue: Value?
    public init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try container.decode(Value.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(wrappedValue) } else { try container.encodeNil() }
    }
}

public enum AdeLocale: String, Codable, Equatable {
    case en, es
}

public enum PersonStatus: String, Codable, Equatable {
    case active, inactive
}

public enum EventStatus: String, Codable, Equatable {
    case draft, scheduled, completed, cancelled
}

public enum AttendanceState: String, Codable, Equatable, CaseIterable {
    case present, absent, excused, pending
}

public enum VolunteerState: String, Codable, Equatable, CaseIterable {
    case interested, selected, completed, declined, absent
}

public enum ExclusionReason: String, Codable, Equatable {
    case notParticipant = "not-participant"
    case notMemberOnDate = "not-member-on-date"
    case cancelled
    case notCounting = "not-counting"
    case unrecorded
    case pending
    case excused
}

public enum EntityType: String, Codable, Equatable, CaseIterable {
    case space, person, group, membership, period, component, category, event, attendance, volunteering, template, asset
}

public enum AssetMime: String, Codable, Equatable {
    case png = "image/png"
    case jpeg = "image/jpeg"
    case pdf = "application/pdf"
}

public enum PageSize: String, Codable, Equatable {
    case letter, a4
}

public enum TextAlign: String, Codable, Equatable {
    case left, center, right
}

public enum ConflictResolution: String, Codable, Equatable {
    case pending
    case keptLocal = "kept-local"
    case keptRemote = "kept-remote"
    case keptBoth = "kept-both"
}

public enum TextBinding: String, Codable, Equatable, CaseIterable {
    case spaceName = "space.name"
    case periodName = "period.name"
    case periodRange = "period.range"
    case eventTitle = "event.title"
    case eventDate = "event.date"
    case eventComponent = "event.component"
    case eventCategory = "event.category"
    case eventStatus = "event.status"
    case groupName = "group.name"
    case generatedAt
}

public enum ListBinding: String, Codable, Equatable, CaseIterable {
    case eventParticipants = "event.participants"
    case eventAttendance = "event.attendance"
    case eventVolunteers = "event.volunteers"
    case periodParticipation = "period.participation"
    case groupMembers = "group.members"
}

public enum ScoreFactorCode: String, Codable, Equatable {
    case completed
    case recentCompleted
    case sameComponentCompleted
    case selected
    case priorInterested
    case interestedNow
    case declined
    case absent
    case attendancePresent
    case noHistory = "no-history"
}

public struct Actor: Codable, Equatable {
    public var id: String
    public var name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Space: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: String
    public var updatedAt: String
}

public struct Person: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var name: String
    public var email: String
    public var notes: String
    public var status: PersonStatus
    public var createdAt: String
    public var updatedAt: String
}

public struct Group: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var name: String
    public var description: String
    public var createdAt: String
    public var updatedAt: String
}

public struct GroupMembership: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var groupId: String
    public var personId: String
    public var startDate: String
    @Nullable public var endDate: String?
    public var createdAt: String
    public var updatedAt: String
}

public struct Period: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var name: String
    public var startDate: String
    public var endDate: String
    public var createdAt: String
    public var updatedAt: String
}

public struct ActivityComponent: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var name: String
    public var description: String
    public var createdAt: String
    public var updatedAt: String
}

public struct Category: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var componentId: String
    public var name: String
    public var description: String
    public var createdAt: String
    public var updatedAt: String
}

public struct AdeEvent: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var title: String
    public var description: String
    public var date: String
    public var componentId: String
    @Nullable public var categoryId: String?
    public var participantIds: [String]
    @Nullable public var capacity: Int?
    public var countsForAttendance: Bool
    public var status: EventStatus
    @Nullable public var volunteerCapacity: Int?
    @Nullable public var duplicatedFromId: String?
    public var createdAt: String
    public var updatedAt: String
}

public struct AttendanceHistoryEntry: Codable, Equatable {
    public var at: String
    public var actorId: String
    @Nullable public var previousState: AttendanceState?
    public var nextState: AttendanceState
    public var previousNote: String
    public var nextNote: String
}

public struct AttendanceRecord: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var eventId: String
    public var personId: String
    public var state: AttendanceState
    public var note: String
    public var history: [AttendanceHistoryEntry]
    public var createdAt: String
    public var updatedAt: String
}

public struct VolunteerHistoryEntry: Codable, Equatable {
    public var at: String
    public var actorId: String
    @Nullable public var previousState: VolunteerState?
    public var nextState: VolunteerState
    public var previousNote: String
    public var nextNote: String
}

public struct VolunteerRecord: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var eventId: String
    public var personId: String
    public var state: VolunteerState
    public var note: String
    public var history: [VolunteerHistoryEntry]
    public var createdAt: String
    public var updatedAt: String
}

public struct TemplateTextElement: Codable, Equatable {
    public var id: String
    public var type: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var text: String
    @Nullable public var binding: TextBinding?
    public var fontSize: Double
    public var align: TextAlign
    public init(id: String, x: Double, y: Double, width: Double, height: Double, text: String, binding: TextBinding?, fontSize: Double, align: TextAlign) {
        self.id = id
        self.type = "text"
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
        self.binding = binding
        self.fontSize = fontSize
        self.align = align
    }
}

public struct TemplateImageElement: Codable, Equatable {
    public var id: String
    public var type: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var assetId: String
    public init(id: String, x: Double, y: Double, width: Double, height: Double, assetId: String) {
        self.id = id
        self.type = "image"
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.assetId = assetId
    }
}

public struct TemplateColumnsElement: Codable, Equatable {
    public var id: String
    public var type: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var columns: Int
    public var gap: Double
    public var binding: ListBinding
    public var fontSize: Double
    public init(id: String, x: Double, y: Double, width: Double, height: Double, columns: Int, gap: Double, binding: ListBinding, fontSize: Double) {
        self.id = id
        self.type = "columns"
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.columns = columns
        self.gap = gap
        self.binding = binding
        self.fontSize = fontSize
    }
}

public enum TemplateElement: Codable, Equatable {
    case text(TemplateTextElement)
    case image(TemplateImageElement)
    case columns(TemplateColumnsElement)

    public var id: String {
        switch self {
        case .text(let value): return value.id
        case .image(let value): return value.id
        case .columns(let value): return value.id
        }
    }

    public var x: Double {
        switch self {
        case .text(let value): return value.x
        case .image(let value): return value.x
        case .columns(let value): return value.x
        }
    }

    public var y: Double {
        switch self {
        case .text(let value): return value.y
        case .image(let value): return value.y
        case .columns(let value): return value.y
        }
    }

    public var width: Double {
        switch self {
        case .text(let value): return value.width
        case .image(let value): return value.width
        case .columns(let value): return value.width
        }
    }

    public var height: Double {
        switch self {
        case .text(let value): return value.height
        case .image(let value): return value.height
        case .columns(let value): return value.height
        }
    }

    private enum Kind: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: Kind.self)
        switch try kind.decode(String.self, forKey: .type) {
        case "text": self = .text(try TemplateTextElement(from: decoder))
        case "image": self = .image(try TemplateImageElement(from: decoder))
        case "columns": self = .columns(try TemplateColumnsElement(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "element"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value): try value.encode(to: encoder)
        case .image(let value): try value.encode(to: encoder)
        case .columns(let value): try value.encode(to: encoder)
        }
    }
}

public struct TextElementDraft {
    public var id: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var text: String
    public var binding: TextBinding?
    public var fontSize: Double
    public var align: TextAlign
    public init(id: String? = nil, x: Double, y: Double, width: Double, height: Double, text: String, binding: TextBinding?, fontSize: Double, align: TextAlign) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
        self.binding = binding
        self.fontSize = fontSize
        self.align = align
    }
}

public struct ImageElementDraft {
    public var id: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var assetId: String
    public init(id: String? = nil, x: Double, y: Double, width: Double, height: Double, assetId: String) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.assetId = assetId
    }
}

public struct ColumnsElementDraft {
    public var id: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var columns: Int
    public var gap: Double
    public var binding: ListBinding
    public var fontSize: Double
    public init(id: String? = nil, x: Double, y: Double, width: Double, height: Double, columns: Int, gap: Double, binding: ListBinding, fontSize: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.columns = columns
        self.gap = gap
        self.binding = binding
        self.fontSize = fontSize
    }
}

public enum ElementDraft {
    case text(TextElementDraft)
    case image(ImageElementDraft)
    case columns(ColumnsElementDraft)
}

public struct DocumentTemplate: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var name: String
    public var description: String
    public var pageSize: PageSize
    @Nullable public var backgroundAssetId: String?
    public var elements: [TemplateElement]
    public var createdAt: String
    public var updatedAt: String
}

public struct Asset: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var name: String
    public var mime: AssetMime
    public var dataBase64: String
    public var createdAt: String
    @Nullable public var deletedAt: String?
}

public struct Tombstone: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var entityType: EntityType
    public var entityId: String
    public var naturalKey: String
    public var deletedAt: String
    public var deletedBy: String
    public var payload: JSONValue
}

public struct ConflictRecord: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var entityType: EntityType
    public var key: String
    @Nullable public var localEntityId: String?
    @Nullable public var remoteEntityId: String?
    public var local: JSONValue
    public var remote: JSONValue
    public var remoteDeleted: Bool
    public var createdAt: String
    @Nullable public var resolvedAt: String?
    public var resolution: ConflictResolution
    @Nullable public var materializedId: String?
}

public struct SpaceSnapshot: Codable, Equatable {
    public var space: Space
    public var people: [Person]
    public var groups: [Group]
    public var memberships: [GroupMembership]
    public var periods: [Period]
    public var components: [ActivityComponent]
    public var categories: [Category]
    public var events: [AdeEvent]
    public var attendance: [AttendanceRecord]
    public var volunteering: [VolunteerRecord]
    public var templates: [DocumentTemplate]
    public var assets: [Asset]
    public var conflicts: [ConflictRecord]
    public var tombstones: [Tombstone]
}

public struct Revision: Codable, Equatable, Identifiable {
    public var id: String
    public var spaceId: String
    public var at: String
    public var actorId: String
    public var action: String
    public var params: [String: String]
    public var snapshot: SpaceSnapshot
}

public struct SpaceHistory: Codable, Equatable {
    public var spaceId: String
    public var revisionIds: [String]
    public var cursor: Int
}

public struct Database: Codable, Equatable {
    public var format: String
    public var actor: Actor
    public var locale: AdeLocale
    public var spaces: [Space]
    public var people: [Person]
    public var groups: [Group]
    public var memberships: [GroupMembership]
    public var periods: [Period]
    public var components: [ActivityComponent]
    public var categories: [Category]
    public var events: [AdeEvent]
    public var attendance: [AttendanceRecord]
    public var volunteering: [VolunteerRecord]
    public var templates: [DocumentTemplate]
    public var assets: [Asset]
    public var conflicts: [ConflictRecord]
    public var tombstones: [Tombstone]
    public var revisions: [Revision]
    public var histories: [SpaceHistory]
}

public struct SyncBundle: Codable, Equatable {
    public var format: String
    public var exportedAt: String
    public var actor: Actor
    public var snapshot: SpaceSnapshot
    public var tombstones: [Tombstone]
}

public struct BackupFile: Codable, Equatable {
    public var format: String
    public var exportedAt: String
    public var database: Database
}

public struct ReduceContext {
    public var now: String
    public var actorId: String
    public var newId: () -> String
    public init(now: String, actorId: String, newId: @escaping () -> String) {
        self.now = now
        self.actorId = actorId
        self.newId = newId
    }
}

public struct AttendanceLine: Equatable {
    public var eventId: String
    public var personId: String
    public var outcome: String
    public var reason: ExclusionReason?
    public var state: AttendanceState?
}

public struct AttendanceBreakdown: Equatable {
    public var present: Int
    public var absent: Int
    public var excused: Int
    public var pending: Int
    public var unrecorded: Int
    public var excludedCancelled: Int
    public var excludedNotCounting: Int
    public var excludedNotParticipant: Int
    public var excludedNotMember: Int
    public var denominator: Int
    public var percentage: Double?
    public var formula: String
    public var lines: [AttendanceLine]
}

public struct AttendanceQuery {
    public var spaceId: String
    public var periodId: String?
    public var groupId: String?
    public var componentId: String?
    public var categoryId: String?
    public var personId: String?
    public var eventId: String?
    public init(spaceId: String, periodId: String? = nil, groupId: String? = nil, componentId: String? = nil, categoryId: String? = nil, personId: String? = nil, eventId: String? = nil) {
        self.spaceId = spaceId
        self.periodId = periodId
        self.groupId = groupId
        self.componentId = componentId
        self.categoryId = categoryId
        self.personId = personId
        self.eventId = eventId
    }
}

public struct ScoreFactor: Equatable {
    public var code: ScoreFactorCode
    public var count: Int
    public var points: Int
}

public struct VolunteerSuggestion: Equatable, Identifiable {
    public var personId: String
    public var name: String
    public var score: Int
    public var completedCount: Int
    public var eligible: Bool
    public var factors: [ScoreFactor]
    public var id: String { personId }
}

public struct DocumentLabels {
    public var unrecorded: String
    public var attendance: [AttendanceState: String]
    public var volunteer: [VolunteerState: String]
    public var eventStatus: [EventStatus: String]
    public var percent: (Double?) -> String
    public var counts: (Int, Int) -> String
    public var separator: String
    public init(unrecorded: String, attendance: [AttendanceState: String], volunteer: [VolunteerState: String], eventStatus: [EventStatus: String], percent: @escaping (Double?) -> String, counts: @escaping (Int, Int) -> String, separator: String) {
        self.unrecorded = unrecorded
        self.attendance = attendance
        self.volunteer = volunteer
        self.eventStatus = eventStatus
        self.percent = percent
        self.counts = counts
        self.separator = separator
    }
}

public struct TemplateDataContext {
    public var spaceId: String
    public var periodId: String?
    public var eventId: String?
    public var groupId: String?
    public var generatedAt: String
    public init(spaceId: String, periodId: String?, eventId: String?, groupId: String?, generatedAt: String) {
        self.spaceId = spaceId
        self.periodId = periodId
        self.eventId = eventId
        self.groupId = groupId
        self.generatedAt = generatedAt
    }
}

public struct PlannedText: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var text: String
    public var fontSize: Double
    public var align: TextAlign
}

public struct PlannedImage: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var assetId: String
}

public enum PlannedItem: Equatable {
    case text(PlannedText)
    case image(PlannedImage)
}

public struct PlannedPage: Equatable {
    public var width: Double
    public var height: Double
    public var backgroundAssetId: String?
    public var backgroundPageIndex: Int
    public var items: [PlannedItem]
}

public enum Action {
    case setLocale(AdeLocale)
    case setActorName(String)
    case createSpace(name: String)
    case renameSpace(spaceId: String, name: String)
    case createPerson(spaceId: String, name: String, email: String, notes: String, status: PersonStatus)
    case updatePerson(spaceId: String, personId: String, name: String, email: String, notes: String, status: PersonStatus)
    case deletePerson(spaceId: String, personId: String)
    case createGroup(spaceId: String, name: String, description: String)
    case updateGroup(spaceId: String, groupId: String, name: String, description: String)
    case deleteGroup(spaceId: String, groupId: String)
    case addMembership(spaceId: String, groupId: String, personId: String, startDate: String, endDate: String?)
    case updateMembership(spaceId: String, membershipId: String, startDate: String, endDate: String?)
    case deleteMembership(spaceId: String, membershipId: String)
    case createPeriod(spaceId: String, name: String, startDate: String, endDate: String)
    case updatePeriod(spaceId: String, periodId: String, name: String, startDate: String, endDate: String)
    case deletePeriod(spaceId: String, periodId: String)
    case createComponent(spaceId: String, name: String, description: String)
    case updateComponent(spaceId: String, componentId: String, name: String, description: String)
    case deleteComponent(spaceId: String, componentId: String)
    case createCategory(spaceId: String, componentId: String, name: String, description: String)
    case updateCategory(spaceId: String, categoryId: String, name: String, description: String)
    case deleteCategory(spaceId: String, categoryId: String)
    case createEvent(spaceId: String, title: String, description: String, date: String, componentId: String, categoryId: String?, capacity: Int?, volunteerCapacity: Int?, countsForAttendance: Bool, participantIds: [String])
    case updateEvent(spaceId: String, eventId: String, title: String, description: String, date: String, componentId: String, categoryId: String?, capacity: Int?, volunteerCapacity: Int?, countsForAttendance: Bool)
    case setEventStatus(spaceId: String, eventId: String, status: EventStatus)
    case setEventParticipants(spaceId: String, eventId: String, participantIds: [String])
    case duplicateEvent(spaceId: String, eventId: String, titleSuffix: String)
    case deleteEvent(spaceId: String, eventId: String)
    case setAttendance(spaceId: String, eventId: String, personId: String, state: AttendanceState, note: String)
    case setVolunteerState(spaceId: String, eventId: String, personId: String, state: VolunteerState, note: String)
    case createTemplate(spaceId: String, name: String, description: String, pageSize: PageSize, backgroundAssetId: String?, elements: [ElementDraft])
    case updateTemplate(spaceId: String, templateId: String, name: String, description: String, pageSize: PageSize, backgroundAssetId: String?, elements: [ElementDraft])
    case deleteTemplate(spaceId: String, templateId: String)
    case addAsset(spaceId: String, name: String, mime: AssetMime, dataBase64: String)
    case deleteAsset(spaceId: String, assetId: String)
    case undo(spaceId: String)
    case redo(spaceId: String)
    case restoreRevision(spaceId: String, revisionId: String)
    case importBackup(JSONValue)
    case importSync(JSONValue)
    case resolveConflict(spaceId: String, conflictId: String, resolution: ConflictResolution)
    case loadDemo
}
