import Foundation

public let defaultDocumentLabels = DocumentLabels(
    unrecorded: "unrecorded",
    attendance: [
        .present: "present", .absent: "absent", .excused: "excused", .pending: "pending",
    ],
    volunteer: [
        .interested: "interested", .selected: "selected", .completed: "completed", .declined: "declined", .absent: "absent",
    ],
    eventStatus: [
        .draft: "draft", .scheduled: "scheduled", .completed: "completed", .cancelled: "cancelled",
    ],
    percent: formatPercent,
    counts: { present, absent in "\(present)/\(present + absent)" },
    separator: " - "
)

public func attendanceSummaryElements() -> [ElementDraft] {
    [
        .text(TextElementDraft(x: 48, y: 48, width: 516, height: 28, text: "Attendance summary", binding: nil, fontSize: 18, align: .left)),
        .text(TextElementDraft(x: 48, y: 84, width: 516, height: 18, text: "", binding: .spaceName, fontSize: 12, align: .left)),
        .text(TextElementDraft(x: 48, y: 106, width: 250, height: 18, text: "", binding: .periodName, fontSize: 12, align: .left)),
        .text(TextElementDraft(x: 310, y: 106, width: 254, height: 18, text: "", binding: .periodRange, fontSize: 12, align: .right)),
        .columns(ColumnsElementDraft(x: 48, y: 140, width: 516, height: 600, columns: 2, gap: 16, binding: .periodParticipation, fontSize: 11)),
    ]
}

func validateElements(_ db: Database, _ spaceId: String, _ elements: [TemplateElement], _ backgroundAssetId: String?) -> CoreResult<Bool> {
    if let backgroundAssetId {
        guard let asset = db.assets.first(where: { $0.id == backgroundAssetId }),
              asset.spaceId == spaceId, asset.deletedAt == nil, asset.mime == .pdf else {
            return err(.ASSET_NOT_FOUND)
        }
    }
    for element in elements {
        if !element.x.isFinite || !element.y.isFinite || !element.width.isFinite || !element.height.isFinite || element.width <= 0 || element.height <= 0 {
            return err(.INVALID_TEMPLATE)
        }
        switch element {
        case .text(let text):
            if text.fontSize <= 0 { return err(.INVALID_TEMPLATE) }
        case .columns(let columns):
            if columns.columns < 1 || columns.gap < 0 || columns.fontSize <= 0 { return err(.INVALID_TEMPLATE) }
        case .image(let image):
            guard let asset = db.assets.first(where: { $0.id == image.assetId }),
                  asset.spaceId == spaceId, asset.deletedAt == nil, asset.mime == .png || asset.mime == .jpeg else {
                return err(.ASSET_NOT_FOUND)
            }
        }
    }
    return ok(true)
}

public func planDocument(_ db: Database, _ template: DocumentTemplate, _ context: TemplateDataContext, labels: DocumentLabels = defaultDocumentLabels) -> CoreResult<[PlannedPage]> {
    if template.spaceId != context.spaceId { return err(.NOT_FOUND) }
    let valid = validateElements(db, template.spaceId, template.elements, template.backgroundAssetId)
    if !valid.isOk { return err(valid.error!.code, valid.error!.params) }
    let page = PageMetrics.size(template.pageSize)
    var staticItems: [PlannedItem] = []
    for element in template.elements {
        switch element {
        case .text(let text):
            staticItems.append(.text(PlannedText(
                x: text.x, y: text.y, width: text.width, height: text.height,
                text: resolveText(db, context, labels, text.binding, text.text),
                fontSize: text.fontSize, align: text.align
            )))
        case .image(let image):
            staticItems.append(.image(PlannedImage(x: image.x, y: image.y, width: image.width, height: image.height, assetId: image.assetId)))
        case .columns:
            break
        }
    }
    let flows: [TemplateColumnsElement] = template.elements.compactMap {
        if case .columns(let columns) = $0 { return columns }
        return nil
    }
    let pageCount = max(1, flows.map { element -> Int in
        let items = resolveList(db, context, labels, element.binding)
        let perColumn = columnCapacity(element.height, element.fontSize)
        let perPage = perColumn * element.columns
        return max(1, Int(ceil(Double(items.count) / Double(perPage))))
    }.max() ?? 1)
    var pages: [PlannedPage] = []
    for pageIndex in 0..<pageCount {
        var items = staticItems
        for element in flows {
            let lines = resolveList(db, context, labels, element.binding).map {
                truncate($0, fontSize: element.fontSize, width: columnWidth(element.width, element.columns, element.gap))
            }
            let perColumn = columnCapacity(element.height, element.fontSize)
            let perPage = perColumn * element.columns
            let start = pageIndex * perPage
            let end = min(lines.count, start + perPage)
            if start < end {
                let slice = Array(lines[start..<end])
                let colWidth = columnWidth(element.width, element.columns, element.gap)
                let lineHeight = element.fontSize * 1.35
                for (index, line) in slice.enumerated() {
                    let column = index / perColumn
                    let row = index % perColumn
                    items.append(.text(PlannedText(
                        x: element.x + Double(column) * (colWidth + element.gap),
                        y: element.y + Double(row) * lineHeight,
                        width: colWidth,
                        height: lineHeight,
                        text: line,
                        fontSize: element.fontSize,
                        align: .left
                    )))
                }
            }
        }
        pages.append(PlannedPage(
            width: page.width, height: page.height,
            backgroundAssetId: template.backgroundAssetId,
            backgroundPageIndex: pageIndex,
            items: items
        ))
    }
    return ok(pages)
}

private func personName(_ db: Database, _ personId: String) -> String {
    db.people.first { $0.id == personId }?.name ?? personId
}

private func resolveText(_ db: Database, _ context: TemplateDataContext, _ labels: DocumentLabels, _ binding: TextBinding?, _ literal: String) -> String {
    guard let binding else { return literal }
    let space = db.spaces.first { $0.id == context.spaceId }
    let period = context.periodId.flatMap { id in db.periods.first { $0.id == id } }
    let event = context.eventId.flatMap { id in db.events.first { $0.id == id } }
    let group = context.groupId.flatMap { id in db.groups.first { $0.id == id } }
    switch binding {
    case .spaceName: return space?.name ?? ""
    case .periodName: return period?.name ?? ""
    case .periodRange: return period.map { "\($0.startDate) - \($0.endDate)" } ?? ""
    case .eventTitle: return event?.title ?? ""
    case .eventDate: return event?.date ?? ""
    case .eventComponent: return db.components.first { $0.id == event?.componentId }?.name ?? ""
    case .eventCategory: return db.categories.first { $0.id == event?.categoryId }?.name ?? ""
    case .eventStatus: return event.map { labels.eventStatus[$0.status] ?? "" } ?? ""
    case .groupName: return group?.name ?? ""
    case .generatedAt: return context.generatedAt
    }
}

private func memberDate(_ db: Database, _ context: TemplateDataContext) -> String {
    if let periodId = context.periodId, let period = db.periods.first(where: { $0.id == periodId }) {
        return period.endDate
    }
    if let eventId = context.eventId, let event = db.events.first(where: { $0.id == eventId }) {
        return event.date
    }
    return String(context.generatedAt.prefix(10))
}

private func resolveList(_ db: Database, _ context: TemplateDataContext, _ labels: DocumentLabels, _ binding: ListBinding) -> [String] {
    if binding == .eventParticipants || binding == .eventAttendance || binding == .eventVolunteers {
        guard let eventId = context.eventId, let event = db.events.first(where: { $0.id == eventId }) else { return [] }
        if binding == .eventParticipants { return event.participantIds.map { personName(db, $0) } }
        if binding == .eventAttendance {
            return event.participantIds.map { personId in
                let record = db.attendance.first { $0.eventId == event.id && $0.personId == personId }
                let state = record.flatMap { labels.attendance[$0.state] } ?? labels.unrecorded
                return personName(db, personId) + labels.separator + state
            }
        }
        return db.volunteering.filter { $0.eventId == event.id }.map { record in
            personName(db, record.personId) + labels.separator + (labels.volunteer[record.state] ?? record.state.rawValue)
        }
    }
    if binding == .periodParticipation {
        guard context.periodId != nil else { return [] }
        return attendanceByPerson(db, AttendanceQuery(spaceId: context.spaceId, periodId: context.periodId, groupId: context.groupId)).map { row in
            "\(row.person.name)\(labels.separator)\(labels.percent(row.breakdown.percentage)) (\(labels.counts(row.breakdown.present, row.breakdown.absent)))"
        }
    }
    guard let groupId = context.groupId else { return [] }
    return membersAt(db, groupId: groupId, date: memberDate(db, context)).map(\.name)
}

private func truncate(_ text: String, fontSize: Double, width: Double) -> String {
    let maxChars = max(1, Int(floor(width / (fontSize * 0.5))))
    if text.count <= maxChars { return text }
    if maxChars == 1 { return "." }
    let end = text.index(text.startIndex, offsetBy: maxChars - 3)
    return String(text[..<end]) + "..."
}

private func columnCapacity(_ height: Double, _ fontSize: Double) -> Int {
    max(1, Int(floor(height / (fontSize * 1.35))))
}

private func columnWidth(_ width: Double, _ columns: Int, _ gap: Double) -> Double {
    (width - gap * Double(columns - 1)) / Double(columns)
}
