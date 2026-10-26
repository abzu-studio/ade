import SwiftUI

struct EventsScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var adding = false
    @State private var confirmCancel = false

    var body: some View {
        SpacePage(title: store.text("events.title")) {
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Verb(title: store.text("events.add")) { adding = true }
                        .padding(.horizontal, 12)
                        .disabled(store.components(in: store.spaceId ?? "").isEmpty)
                    if events.isEmpty {
                        Text(store.text("events.empty"))
                            .font(AdeFont.body(14))
                            .foregroundStyle(Clay.umber)
                            .padding(16)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(events) { event in
                                HStack(spacing: 6) {
                                    ClayRow(title: event.title, subtitle: event.date, selected: store.eventId == event.id) {
                                        store.eventId = event.id
                                    }
                                    Stamp(title: store.text("status.\(event.status.rawValue)"), kind: stampKind(event.status))
                                    if event.status == .scheduled || event.status == .completed || event.status == .draft {
                                        Verb(title: store.text("events.cancel")) {
                                            guard let spaceId = store.spaceId else { return }
                                            store.perform(.setEventStatus(spaceId: spaceId, eventId: event.id, status: .cancelled))
                                        }
                                    }
                                }
                                .padding(.trailing, 8)
                            }
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 380)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $adding) { EventSheet() }
        .confirmationDialog(store.text("events.cancel"), isPresented: $confirmCancel, titleVisibility: .visible) {
            Button(store.text("events.cancel"), role: .destructive) { setStatus(.cancelled) }
            Button(store.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(store.text("events.cancelHelp"))
        }
    }

    private var events: [AdeEvent] { store.events(in: store.spaceId ?? "") }
    private var event: AdeEvent? { events.first { $0.id == store.eventId } }

    @ViewBuilder private var detail: some View {
        if let event {
            EventDetail(event: event, confirmCancel: $confirmCancel)
        } else {
            Text(store.text("events.empty"))
                .font(AdeFont.body(15))
                .foregroundStyle(Clay.umber)
                .padding(28)
        }
    }

    private func setStatus(_ status: EventStatus) {
        guard let spaceId = store.spaceId, let event else { return }
        store.perform(.setEventStatus(spaceId: spaceId, eventId: event.id, status: status))
    }

    private func stampKind(_ status: EventStatus) -> Stamp.Kind {
        switch status {
        case .scheduled: return .scheduled
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .draft: return .plain
        }
    }
}

struct EventDetail: View {
    @EnvironmentObject private var store: AdeStore
    var event: AdeEvent
    @Binding var confirmCancel: Bool
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                attendanceSection
                volunteerSection
                detailsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { syncRoster() }
        .onChange(of: event.id) { _, _ in syncRoster() }
        .onChange(of: event.participantIds) { _, _ in syncRoster() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(AdeFont.display(36))
                .tracking(1)
                .foregroundStyle(Clay.umber)
            Text(event.date)
                .font(AdeFont.kicker(12))
                .foregroundStyle(Clay.ink)
            HStack(spacing: 8) {
                ForEach(eventTransitions[event.status] ?? [], id: \.self) { next in
                    if next == .cancelled {
                        Verb(title: store.text("events.cancel")) { confirmCancel = true }
                    } else {
                        Verb(title: statusTitle(next)) {
                            guard let spaceId = store.spaceId else { return }
                            store.perform(.setEventStatus(spaceId: spaceId, eventId: event.id, status: next))
                        }
                    }
                }
                Verb(title: store.text("events.duplicate")) {
                    guard let spaceId = store.spaceId else { return }
                    store.perform(.duplicateEvent(spaceId: spaceId, eventId: event.id, titleSuffix: store.text("common.copySuffix")))
                }
                if event.status == .draft {
                    Verb(title: store.text("action.delete")) {
                        guard let spaceId = store.spaceId else { return }
                        store.perform(.deleteEvent(spaceId: spaceId, eventId: event.id))
                        if store.lastError == nil { store.eventId = nil }
                    }
                }
            }
            if let breakdown = running {
                Text(formatPercent(breakdown.percentage))
                    .font(AdeFont.display(48))
                    .foregroundStyle(Clay.ink)
                Text(store.text("attendance.formula"))
                    .font(AdeFont.body(13))
                    .foregroundStyle(Clay.umber)
                Text(countLine(breakdown))
                    .font(AdeFont.kicker(12))
                    .foregroundStyle(Clay.umber)
            }
        }
    }

    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.text("events.attendance").uppercased())
                .font(AdeFont.kicker(11))
                .tracking(1.3)
                .foregroundStyle(Clay.ink)
            if event.status != .scheduled && event.status != .completed {
                Text(store.text("attendance.notAllowed"))
                    .font(AdeFont.body(14))
                    .foregroundStyle(Clay.umber)
            } else if event.participantIds.isEmpty {
                Text(store.text("attendance.empty"))
                    .font(AdeFont.body(14))
                    .foregroundStyle(Clay.umber)
            } else {
                Text(store.text("attendance.shortcuts"))
                    .font(AdeFont.body(13))
                    .foregroundStyle(Clay.umber.opacity(0.8))
                ForEach(roster) { person in
                    attendanceRow(person, index: roster.firstIndex(where: { $0.id == person.id }) ?? 0)
                }
            }
        }
    }

    private var volunteerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.text("events.volunteers").uppercased())
                .font(AdeFont.kicker(11))
                .tracking(1.3)
                .foregroundStyle(Clay.ink)
            Text(store.text("volunteers.manual"))
                .font(AdeFont.body(14))
                .foregroundStyle(Clay.umber)
            Text(store.text("volunteers.capacity", [
                "used": String(consumingVolunteerCount(store.database, eventId: event.id)),
                "capacity": event.volunteerCapacity.map(String.init) ?? store.text("common.unlimited"),
            ]))
            .font(AdeFont.kicker(12))
            .foregroundStyle(Clay.umber)
            Text(store.text("volunteers.recentDays", ["days": String(VolunteerWeights.recentDays)]))
                .font(AdeFont.body(13))
                .foregroundStyle(Clay.umber.opacity(0.8))
            if event.status == .cancelled {
                Text(store.text("volunteers.notAllowed")).font(AdeFont.body(14)).foregroundStyle(Clay.umber)
            } else {
                let suggestions = suggestVolunteers(store.database, eventId: event.id)
                if suggestions.isEmpty {
                    Text(store.text("volunteers.empty")).font(AdeFont.body(14)).foregroundStyle(Clay.umber)
                }
                ForEach(suggestions) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.text("events.details").uppercased())
                .font(AdeFont.kicker(11))
                .tracking(1.3)
                .foregroundStyle(Clay.ink)
            if !event.description.isEmpty {
                Text(event.description).font(AdeFont.body(14)).foregroundStyle(Clay.umber)
            }
            let component = store.database.components.first { $0.id == event.componentId }?.name ?? ""
            let category = store.database.categories.first { $0.id == event.categoryId }?.name
            Text("\(store.text("taxonomy.component")): \(component)")
                .font(AdeFont.body(14))
                .foregroundStyle(Clay.umber)
            if let category {
                Text("\(store.text("taxonomy.category")): \(category)")
                    .font(AdeFont.body(14))
                    .foregroundStyle(Clay.umber)
            }
            Text(store.text("events.counts") + ": " + (event.countsForAttendance ? store.text("common.active") : store.text("common.inactive")))
                .font(AdeFont.body(13))
                .foregroundStyle(Clay.umber)
            if event.status == .cancelled {
                Text(store.text("events.locked")).font(AdeFont.body(13)).foregroundStyle(Clay.umber)
            }
            Text(store.text("events.participants").uppercased())
                .font(AdeFont.kicker(11))
                .tracking(1.2)
                .foregroundStyle(Clay.ink)
                .padding(.top, 6)
            ForEach(store.people(in: event.spaceId)) { person in
                Toggle(person.name, isOn: participantBinding(person.id))
                    .font(AdeFont.body(14))
                    .foregroundStyle(Clay.umber)
                    .disabled(event.status == .cancelled)
                    .tint(Clay.ink)
            }
        }
    }

    private var roster: [Person] {
        event.participantIds.compactMap { id in store.database.people.first { $0.id == id } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var running: AttendanceBreakdown? {
        guard let spaceId = store.spaceId else { return nil }
        return computeAttendance(store.database, AttendanceQuery(spaceId: spaceId, eventId: event.id))
    }

    private func syncRoster() {
        store.setAttendanceRoster(roster.map(\.id))
        if let personId = roster.first?.id,
           let record = store.database.attendance.first(where: { $0.eventId == event.id && $0.personId == personId }) {
            note = record.note
        }
    }

    private func attendanceRow(_ person: Person, index: Int) -> some View {
        let record = store.database.attendance.first { $0.eventId == event.id && $0.personId == person.id }
        let selected = store.attendanceIndex == index
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(person.name)
                    .font(AdeFont.medium(15))
                    .foregroundStyle(Clay.umber)
                Spacer()
                if let record {
                    Stamp(title: store.text("attendance.\(record.state.rawValue)"), kind: .pressed)
                } else {
                    Stamp(title: store.text("attendance.unrecorded"))
                }
            }
            HStack(spacing: 8) {
                ForEach(AttendanceState.allCases, id: \.self) { state in
                    Stamp(title: store.text("attendance.\(state.rawValue)"), kind: record?.state == state ? .pressed : .plain) {
                        guard let spaceId = store.spaceId else { return }
                        store.attendanceIndex = index
                        store.perform(.setAttendance(spaceId: spaceId, eventId: event.id, personId: person.id, state: state, note: record?.note ?? ""))
                    }
                }
            }
            if selected, record != nil {
                ClayField(label: store.text("attendance.note"), text: $note)
                Verb(title: store.text("attendance.saveNote")) {
                    guard let spaceId = store.spaceId, let record else { return }
                    store.perform(.setAttendance(spaceId: spaceId, eventId: event.id, personId: person.id, state: record.state, note: note))
                }
                if record?.history.isEmpty == false {
                    Text(store.text("attendance.history").uppercased())
                        .font(AdeFont.kicker(11))
                        .foregroundStyle(Clay.ink)
                    let history = record?.history ?? []
                    ForEach(Array(history.indices), id: \.self) { index in
                        let entry = history[index]
                        Text("\(formatWhen(entry.at, locale: store.locale)) · \(store.text("attendance.\(entry.nextState.rawValue)"))")
                            .font(AdeFont.kicker(11))
                            .foregroundStyle(Clay.umber)
                    }
                } else {
                    Text(store.text("attendance.noHistory"))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber)
                }
            }
        }
        .padding(8)
        .background(selected ? Clay.tintWash : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            store.attendanceIndex = index
            note = record?.note ?? ""
        }
    }

    private func suggestionRow(_ suggestion: VolunteerSuggestion) -> some View {
        let record = store.database.volunteering.first { $0.eventId == event.id && $0.personId == suggestion.personId }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(suggestion.name).font(AdeFont.medium(15)).foregroundStyle(Clay.umber)
                Spacer()
                Text(store.text("volunteers.score", ["score": String(suggestion.score)]))
                    .font(AdeFont.kicker(11))
                    .foregroundStyle(Clay.ink)
            }
            ForEach(Array(suggestion.factors.indices), id: \.self) { index in
                let factor = suggestion.factors[index]
                Text(store.text("volunteers.factors.\(factor.code.rawValue)", [
                    "count": String(factor.count),
                    "points": String(factor.points),
                ]))
                .font(AdeFont.body(12))
                .foregroundStyle(Clay.umber.opacity(0.85))
            }
            HStack(spacing: 10) {
                ForEach(nextVolunteerStates(record?.state), id: \.self) { state in
                    let selectBlocked = state == .selected && !suggestion.eligible && record?.state != .selected
                    Verb(title: volunteerTitle(state), enabled: !selectBlocked) {
                        guard let spaceId = store.spaceId else { return }
                        store.perform(.setVolunteerState(spaceId: spaceId, eventId: event.id, personId: suggestion.personId, state: state, note: record?.note ?? ""))
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
    }

    private func nextVolunteerStates(_ current: VolunteerState?) -> [VolunteerState] {
        if let current { return volunteerTransitions[current] ?? [] }
        return [.interested, .selected]
    }

    private func volunteerTitle(_ state: VolunteerState) -> String {
        if state == .selected { return store.text("volunteers.select") }
        if state == .interested { return store.text("volunteers.markInterested") }
        return store.text("volunteer.\(state.rawValue)")
    }

    private func statusTitle(_ status: EventStatus) -> String {
        switch status {
        case .scheduled: return event.status == .cancelled ? store.text("events.reopen") : store.text("events.schedule")
        case .completed: return store.text("events.complete")
        case .draft: return store.text("events.backToDraft")
        case .cancelled: return store.text("events.cancel")
        }
    }

    private func countLine(_ breakdown: AttendanceBreakdown) -> String {
        "\(store.text("attendance.present")) \(breakdown.present) · \(store.text("attendance.absent")) \(breakdown.absent) · \(store.text("attendance.excused")) \(breakdown.excused) · \(store.text("attendance.pending")) \(breakdown.pending)"
    }

    private func participantBinding(_ personId: String) -> Binding<Bool> {
        Binding(
            get: { event.participantIds.contains(personId) },
            set: { on in
                guard let spaceId = store.spaceId else { return }
                var ids = event.participantIds
                if on {
                    if !ids.contains(personId) { ids.append(personId) }
                } else {
                    ids.removeAll { $0 == personId }
                }
                store.perform(.setEventParticipants(spaceId: spaceId, eventId: event.id, participantIds: ids))
            }
        )
    }
}

struct EventSheet: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var date = todayISO()
    @State private var componentId = ""
    @State private var categoryId = ""
    @State private var capacity = ""
    @State private var volunteerCapacity = ""
    @State private var counts = true
    @State private var participants: Set<String> = []

    var body: some View {
        SheetFrame(title: store.text("events.add"), saveTitle: store.text("action.create"), saveEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty && !componentId.isEmpty) {
            guard let spaceId = store.spaceId else { return }
            let capacityValue: Int?
            let volunteerValue: Int?
            switch wholeNumber(capacity) {
            case .unlimited: capacityValue = nil
            case .value(let number): capacityValue = number
            case .invalid:
                store.lastError = store.text("error.INVALID_CAPACITY")
                return
            }
            switch wholeNumber(volunteerCapacity) {
            case .unlimited: volunteerValue = nil
            case .value(let number): volunteerValue = number
            case .invalid:
                store.lastError = store.text("error.INVALID_CAPACITY")
                return
            }
            store.perform(.createEvent(
                spaceId: spaceId,
                title: title,
                description: details,
                date: date.trimmingCharacters(in: .whitespaces),
                componentId: componentId,
                categoryId: categoryId.isEmpty ? nil : categoryId,
                capacity: capacityValue,
                volunteerCapacity: volunteerValue,
                countsForAttendance: counts,
                participantIds: Array(participants)
            ))
            if store.lastError == nil {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                store.eventId = store.events(in: spaceId).first { $0.title == trimmed }?.id
                dismiss()
            }
        } content: {
            ClayField(label: store.text("common.name"), text: $title)
            ClayField(label: store.text("common.date"), text: $date)
            ClayField(label: store.text("common.description"), text: $details, axis: .vertical)
            Picker(store.text("taxonomy.component"), selection: $componentId) {
                ForEach(store.components(in: store.spaceId ?? "")) { component in
                    Text(component.name).tag(component.id)
                }
            }
            Picker(store.text("taxonomy.category"), selection: $categoryId) {
                Text(store.text("common.none")).tag("")
                ForEach(store.categories(in: store.spaceId ?? "", componentId: componentId)) { category in
                    Text(category.name).tag(category.id)
                }
            }
            ClayField(label: store.text("events.capacity"), text: $capacity)
            ClayField(label: store.text("events.volunteerCapacity"), text: $volunteerCapacity)
            Toggle(store.text("events.counts"), isOn: $counts).tint(Clay.ink)
            Text(store.text("events.participants").uppercased())
                .font(AdeFont.kicker(11))
                .foregroundStyle(Clay.ink)
            ForEach(store.people(in: store.spaceId ?? "")) { person in
                Toggle(person.name, isOn: Binding(
                    get: { participants.contains(person.id) },
                    set: { on in
                        if on { participants.insert(person.id) } else { participants.remove(person.id) }
                    }
                ))
                .tint(Clay.ink)
            }
        }
        .frame(minWidth: 460)
        .onAppear {
            componentId = store.components(in: store.spaceId ?? "").first?.id ?? ""
        }
        .onChange(of: componentId) { _, _ in categoryId = "" }
    }
}
