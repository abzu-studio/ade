import SwiftUI
import AdeCore

struct ParticipationScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var periodId = ""
    @State private var groupId = ""
    @State private var componentId = ""
    @State private var categoryId = ""
    @State private var showSkipped = false
    @State private var personId = ""

    var body: some View {
        SpacePage(title: store.text("participation.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.text("participation.formula"))
                        .font(AdeFont.body(14))
                        .foregroundStyle(Clay.umber)
                    Text(store.text("participation.explain"))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber.opacity(0.85))
                    Text(store.text("participation.groupRule"))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber.opacity(0.85))
                    if periods.isEmpty {
                        Text(store.text("participation.empty"))
                            .font(AdeFont.body(15))
                            .foregroundStyle(Clay.umber)
                    } else {
                        filters
                        pooled
                        ForEach(rows, id: \.person.id) { row in
                            personRow(row.person, row.breakdown)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: chooseDefaults)
        .onChange(of: store.spaceId) { _, _ in chooseDefaults() }
    }

    private var spaceId: String { store.spaceId ?? "" }
    private var periods: [Period] { store.periods(in: spaceId) }
    private var query: AttendanceQuery {
        AttendanceQuery(
            spaceId: spaceId,
            periodId: periodId.isEmpty ? nil : periodId,
            groupId: groupId.isEmpty ? nil : groupId,
            componentId: componentId.isEmpty ? nil : componentId,
            categoryId: categoryId.isEmpty ? nil : categoryId
        )
    }
    private var pooledBreakdown: AttendanceBreakdown { computeAttendance(store.database, query) }
    private var rows: [(person: Person, breakdown: AttendanceBreakdown)] { attendanceByPerson(store.database, query) }

    private var filters: some View {
        HStack(spacing: 12) {
            picker(store.text("nav.periods"), selection: $periodId, options: periods.map { ($0.id, $0.name) }, allowAll: false)
            picker(store.text("nav.groups"), selection: $groupId, options: store.groups(in: spaceId).map { ($0.id, $0.name) }, allowAll: true)
            picker(store.text("taxonomy.component"), selection: $componentId, options: store.components(in: spaceId).map { ($0.id, $0.name) }, allowAll: true)
            picker(store.text("taxonomy.category"), selection: $categoryId, options: store.categories(in: spaceId, componentId: componentId.isEmpty ? nil : componentId).map { ($0.id, $0.name) }, allowAll: true)
        }
    }

    private var pooled: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.text("participation.pooled").uppercased())
                .font(AdeFont.kicker(11))
                .tracking(1.2)
                .foregroundStyle(Clay.ink)
            Text(formatPercent(pooledBreakdown.percentage))
                .font(AdeFont.display(48))
                .foregroundStyle(Clay.ink)
            Text(store.text("participation.pooledRule"))
                .font(AdeFont.body(13))
                .foregroundStyle(Clay.umber)
            Text("\(store.text("attendance.present")) \(pooledBreakdown.present) · \(store.text("attendance.absent")) \(pooledBreakdown.absent)")
                .font(AdeFont.kicker(12))
                .foregroundStyle(Clay.umber)
        }
        .padding(.vertical, 8)
    }

    private func personRow(_ person: Person, _ breakdown: AttendanceBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                personId = personId == person.id ? "" : person.id
            } label: {
                HStack {
                    Text(person.name).font(AdeFont.medium(16)).foregroundStyle(Clay.umber)
                    Spacer()
                    Text(formatPercent(breakdown.percentage))
                        .font(AdeFont.display(28))
                        .foregroundStyle(Clay.ink)
                    Text("\(breakdown.present)/\(breakdown.denominator)")
                        .font(AdeFont.kicker(12))
                        .foregroundStyle(Clay.umber)
                }
            }
            .buttonStyle(.plain)
            if personId == person.id {
                Toggle(store.text("participation.showSkipped"), isOn: $showSkipped).tint(Clay.ink)
                Text(store.text("participation.detail").uppercased())
                    .font(AdeFont.kicker(11))
                    .foregroundStyle(Clay.ink)
                ForEach(visibleLines(breakdown.lines), id: \.eventId) { line in
                    let title = store.database.events.first { $0.id == line.eventId }?.title ?? line.eventId
                    ClayRow(title: title, subtitle: lineText(line))
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
    }

    private func visibleLines(_ lines: [AttendanceLine]) -> [AttendanceLine] {
        lines.filter { showSkipped || $0.reason != .notParticipant }
    }

    private func lineText(_ line: AttendanceLine) -> String {
        if let state = line.state { return store.text("attendance.\(state.rawValue)") }
        if let reason = line.reason { return store.text("participation.reason.\(reason.rawValue)") }
        return store.text("attendance.unrecorded")
    }

    private func picker(_ label: String, selection: Binding<String>, options: [(String, String)], allowAll: Bool) -> some View {
        Picker(label, selection: selection) {
            if allowAll { Text(store.text("common.all")).tag("") }
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        }
        .font(AdeFont.body(13))
        .frame(maxWidth: 220)
    }

    private func chooseDefaults() {
        if periodId.isEmpty || !periods.contains(where: { $0.id == periodId }) {
            periodId = periods.first?.id ?? ""
        }
    }
}
