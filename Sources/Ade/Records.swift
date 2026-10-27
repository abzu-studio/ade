import SwiftUI
import AdeCore

struct OverviewScreen: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        SpacePage(title: store.text("nav.overview")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(store.text("overview.cycle").uppercased())
                        .font(AdeFont.kicker(11))
                        .tracking(1.3)
                        .foregroundStyle(Clay.ink)
                    VStack(spacing: 0) {
                        ForEach(Array(steps.indices), id: \.self) { index in
                            let step = steps[index]
                            HStack {
                                ClayRow(title: "\(index + 1)  \(step.title)", subtitle: index + 1 == next ? store.text("overview.next") : nil) {
                                    store.go(step.route)
                                }
                                if index + 1 == next {
                                    Stamp(title: store.text("overview.next"))
                                        .padding(.trailing, 8)
                                }
                            }
                        }
                    }
                    Text(store.text("overview.counts").uppercased())
                        .font(AdeFont.kicker(11))
                        .tracking(1.3)
                        .foregroundStyle(Clay.ink)
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        countRow(store.text("nav.people"), people.count)
                        countRow(store.text("nav.groups"), groups.count)
                        countRow(store.text("nav.periods"), periods.count)
                        countRow(store.text("nav.taxonomy"), components.count)
                        countRow(store.text("nav.events"), events.count)
                        countRow(store.text("nav.documents"), templates.count)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private var spaceId: String { store.spaceId ?? "" }
    private var people: [Person] { store.people(in: spaceId) }
    private var groups: [AdeCore.Group] { store.groups(in: spaceId) }
    private var periods: [Period] { store.periods(in: spaceId) }
    private var components: [ActivityComponent] { store.components(in: spaceId) }
    private var events: [AdeEvent] { store.events(in: spaceId) }
    private var templates: [DocumentTemplate] { store.templates(in: spaceId) }
    private var volunteering: [VolunteerRecord] { store.database.volunteering.filter { $0.spaceId == spaceId } }
    private var attendance: [AttendanceRecord] { store.database.attendance.filter { $0.spaceId == spaceId } }

    private var next: Int {
        if people.isEmpty { return 1 }
        if components.isEmpty { return 2 }
        if events.isEmpty { return 3 }
        if volunteering.isEmpty { return 4 }
        if attendance.isEmpty { return 5 }
        return 6
    }

    private var steps: [(title: String, route: AdeRoute)] {
        [
            (store.text("overview.stepPeople"), .people),
            (store.text("overview.stepTaxonomy"), .components),
            (store.text("overview.stepEvent"), .events),
            (store.text("overview.stepVolunteers"), .events),
            (store.text("overview.stepAttendance"), .events),
            (store.text("overview.stepResults"), .participation),
            (store.text("overview.stepDocument"), .documents),
        ]
    }

    private func countRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
            Spacer()
            Text(String(count)).font(AdeFont.kicker(13)).foregroundStyle(Clay.ink)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
    }
}

struct PeopleScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var editing: Person?
    @State private var adding = false
    @State private var confirmDelete = false
    @State private var query = ""

    var body: some View {
        SpacePage(title: store.text("people.title")) {
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Verb(title: store.text("people.add")) { adding = true }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    ClayField(label: store.text("common.search"), text: $query)
                        .padding(.horizontal, 12)
                    if filtered.isEmpty {
                        Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? store.text("people.empty")
                             : store.text("common.noMatches"))
                            .font(AdeFont.body(14))
                            .foregroundStyle(Clay.umber)
                            .padding(16)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filtered) { person in
                                HStack {
                                    ClayRow(
                                        title: person.name,
                                        subtitle: person.email.isEmpty ? store.text(person.status == .active ? "common.active" : "common.inactive") : person.email,
                                        selected: store.personId == person.id
                                    ) { store.personId = person.id }
                                    if person.status == .inactive {
                                        Stamp(title: store.text("common.inactive")).padding(.trailing, 8)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 280, idealWidth: 340)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $adding) { PersonSheet(person: nil) }
        .sheet(item: $editing) { person in PersonSheet(person: person) }
        .confirmationDialog(store.text("people.delete"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(store.text("action.delete"), role: .destructive) { deleteSelected() }
            Button(store.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(store.text("people.deleteHelp"))
        }
    }

    private var spaceId: String { store.spaceId ?? "" }

    private var filtered: [Person] {
        let people = store.people(in: spaceId)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return people }
        return people.filter { $0.name.localizedStandardContains(needle) || $0.email.localizedStandardContains(needle) }
    }

    @ViewBuilder private var detail: some View {
        if let person = store.people(in: spaceId).first(where: { $0.id == store.personId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(person.name)
                        .font(AdeFont.display(36))
                        .tracking(1)
                        .foregroundStyle(Clay.umber)
                    if !person.email.isEmpty {
                        Text(person.email).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
                    }
                    if !person.notes.isEmpty {
                        Text(person.notes).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
                    }
                    Stamp(title: store.text(person.status == .active ? "common.active" : "common.inactive"))
                    HStack(spacing: 16) {
                        Verb(title: store.text("action.edit")) { editing = person }
                        Verb(title: store.text("action.delete")) { confirmDelete = true }
                    }
                    .padding(.top, 8)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(store.text("people.empty"))
                .font(AdeFont.body(15))
                .foregroundStyle(Clay.umber)
                .padding(28)
        }
    }

    private func deleteSelected() {
        guard let spaceId = store.spaceId, let personId = store.personId else { return }
        store.perform(.deletePerson(spaceId: spaceId, personId: personId))
        if store.lastError == nil { store.personId = nil }
    }
}

struct PersonSheet: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    var person: Person?
    @State private var name = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var status: PersonStatus = .active

    var body: some View {
        SheetFrame(
            title: person == nil ? store.text("people.add") : store.text("people.edit"),
            saveTitle: store.text("action.save"),
            saveEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            guard let spaceId = store.spaceId else { return }
            if let person {
                store.perform(.updatePerson(spaceId: spaceId, personId: person.id, name: name, email: email, notes: notes, status: status))
            } else {
                store.perform(.createPerson(spaceId: spaceId, name: name, email: email, notes: notes, status: status))
                if store.lastError == nil {
                    store.personId = store.people(in: spaceId).first { $0.name == name.trimmingCharacters(in: .whitespacesAndNewlines) }?.id
                }
            }
            if store.lastError == nil { dismiss() }
        } content: {
            ClayField(label: store.text("common.name"), text: $name)
            ClayField(label: store.text("common.email"), text: $email)
            ClayField(label: store.text("common.notes"), text: $notes, axis: .vertical)
            Picker(store.text("common.status"), selection: $status) {
                Text(store.text("common.active")).tag(PersonStatus.active)
                Text(store.text("common.inactive")).tag(PersonStatus.inactive)
            }
            .font(AdeFont.body(14))
        }
        .onAppear {
            name = person?.name ?? ""
            email = person?.email ?? ""
            notes = person?.notes ?? ""
            status = person?.status ?? .active
        }
    }
}

struct GroupsScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var adding = false
    @State private var addingMember = false
    @State private var onDate = todayISO()

    var body: some View {
        SpacePage(title: store.text("groups.title")) {
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Verb(title: store.text("groups.add")) { adding = true }
                        .padding(.horizontal, 12)
                    if groups.isEmpty {
                        Text(store.text("groups.empty"))
                            .font(AdeFont.body(14))
                            .foregroundStyle(Clay.umber)
                            .padding(16)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(groups) { group in
                                ClayRow(title: group.name, subtitle: group.description, selected: store.groupId == group.id) {
                                    store.groupId = group.id
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 320)
                detail
            }
        }
        .sheet(isPresented: $adding) { GroupSheet() }
        .sheet(isPresented: $addingMember) {
            if let groupId = store.groupId { MembershipSheet(groupId: groupId) }
        }
    }

    private var spaceId: String { store.spaceId ?? "" }
    private var groups: [AdeCore.Group] { store.groups(in: spaceId) }

    @ViewBuilder private var detail: some View {
        if let group = groups.first(where: { $0.id == store.groupId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(group.name)
                        .font(AdeFont.display(36))
                        .foregroundStyle(Clay.umber)
                    if !group.description.isEmpty {
                        Text(group.description).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
                    }
                    HStack(spacing: 16) {
                        Verb(title: store.text("groups.addMember")) { addingMember = true }
                        Verb(title: store.text("action.delete")) {
                            guard let spaceId = store.spaceId else { return }
                            store.perform(.deleteGroup(spaceId: spaceId, groupId: group.id))
                            if store.lastError == nil { store.groupId = nil }
                        }
                    }
                    Text(store.text("groups.members").uppercased())
                        .font(AdeFont.kicker(11))
                        .tracking(1.2)
                        .foregroundStyle(Clay.ink)
                    let memberships = store.database.memberships.filter { $0.groupId == group.id }
                    if memberships.isEmpty {
                        Text(store.text("common.empty")).font(AdeFont.body(14)).foregroundStyle(Clay.umber)
                    }
                    ForEach(memberships) { membership in
                        membershipRow(membership)
                    }
                    Text(store.text("groups.who").uppercased())
                        .font(AdeFont.kicker(11))
                        .tracking(1.2)
                        .foregroundStyle(Clay.ink)
                        .padding(.top, 8)
                    ClayField(label: store.text("groups.onDate"), text: $onDate)
                    let members = membersAt(store.database, groupId: group.id, date: onDate)
                    if members.isEmpty {
                        Text(store.text("groups.noMembers")).font(AdeFont.body(14)).foregroundStyle(Clay.umber)
                    } else {
                        ForEach(members) { person in
                            ClayRow(title: person.name, subtitle: nil)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(store.text("groups.empty")).font(AdeFont.body(15)).foregroundStyle(Clay.umber).padding(28)
        }
    }

    private func membershipRow(_ membership: GroupMembership) -> some View {
        let name = store.database.people.first { $0.id == membership.personId }?.name ?? store.text("common.person")
        let end = membership.endDate ?? "—"
        return HStack {
            ClayRow(title: name, subtitle: "\(membership.startDate) – \(end)")
            Verb(title: store.text("groups.deleteMembership")) {
                guard let spaceId = store.spaceId else { return }
                store.perform(.deleteMembership(spaceId: spaceId, membershipId: membership.id))
            }
            .padding(.trailing, 4)
        }
    }
}

struct GroupSheet: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""

    var body: some View {
        SheetFrame(title: store.text("groups.add"), saveTitle: store.text("action.create"), saveEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
            guard let spaceId = store.spaceId else { return }
            store.perform(.createGroup(spaceId: spaceId, name: name, description: details))
            if store.lastError == nil {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                store.groupId = store.groups(in: spaceId).first { $0.name == trimmed }?.id
                dismiss()
            }
        } content: {
            ClayField(label: store.text("common.name"), text: $name)
            ClayField(label: store.text("common.description"), text: $details, axis: .vertical)
        }
    }
}

struct MembershipSheet: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    var groupId: String
    @State private var personId = ""
    @State private var start = todayISO()
    @State private var end = ""

    var body: some View {
        SheetFrame(title: store.text("groups.addMember"), saveTitle: store.text("action.add"), saveEnabled: !personId.isEmpty) {
            guard let spaceId = store.spaceId else { return }
            let endDate = end.trimmingCharacters(in: .whitespaces).isEmpty ? nil : end.trimmingCharacters(in: .whitespaces)
            store.perform(.addMembership(spaceId: spaceId, groupId: groupId, personId: personId, startDate: start.trimmingCharacters(in: .whitespaces), endDate: endDate))
            if store.lastError == nil { dismiss() }
        } content: {
            Picker(store.text("common.person"), selection: $personId) {
                Text(store.text("common.none")).tag("")
                ForEach(store.people(in: store.spaceId ?? "")) { person in
                    Text(person.name).tag(person.id)
                }
            }
            ClayField(label: store.text("groups.start"), text: $start)
            ClayField(label: store.text("groups.end"), text: $end)
            Text(store.text("groups.endHelp"))
                .font(AdeFont.body(13))
                .foregroundStyle(Clay.umber.opacity(0.8))
        }
        .onAppear {
            if personId.isEmpty { personId = store.people(in: store.spaceId ?? "").first?.id ?? "" }
        }
    }
}

struct PeriodsScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var adding = false

    var body: some View {
        SpacePage(title: store.text("periods.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Verb(title: store.text("periods.add")) { adding = true }
                    if periods.isEmpty {
                        Text(store.text("periods.empty")).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
                    }
                    ForEach(periods) { period in
                        HStack {
                            ClayRow(title: period.name, subtitle: "\(period.startDate) – \(period.endDate)")
                            Verb(title: store.text("action.delete")) {
                                guard let spaceId = store.spaceId else { return }
                                store.perform(.deletePeriod(spaceId: spaceId, periodId: period.id))
                            }
                        }
                    }
                }
                .padding(28)
            }
        }
        .sheet(isPresented: $adding) { PeriodSheet() }
    }

    private var periods: [Period] { store.periods(in: store.spaceId ?? "") }
}

struct PeriodSheet: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = todayISO()
    @State private var end = todayISO()

    var body: some View {
        SheetFrame(title: store.text("periods.add"), saveTitle: store.text("action.create"), saveEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
            guard let spaceId = store.spaceId else { return }
            store.perform(.createPeriod(spaceId: spaceId, name: name, startDate: start.trimmingCharacters(in: .whitespaces), endDate: end.trimmingCharacters(in: .whitespaces)))
            if store.lastError == nil { dismiss() }
        } content: {
            ClayField(label: store.text("common.name"), text: $name)
            ClayField(label: store.text("periods.start"), text: $start)
            ClayField(label: store.text("periods.end"), text: $end)
        }
    }
}

struct ComponentsScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var addingComponent = false
    @State private var categoryComponent: CategoryTarget?

    var body: some View {
        SpacePage(title: store.text("taxonomy.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Verb(title: store.text("taxonomy.addComponent")) { addingComponent = true }
                    if components.isEmpty {
                        Text(store.text("taxonomy.empty")).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
                    }
                    ForEach(components) { component in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(component.name)
                                    .font(AdeFont.display(28))
                                    .foregroundStyle(Clay.umber)
                                Spacer()
                                Verb(title: store.text("taxonomy.addCategory")) { categoryComponent = CategoryTarget(id: component.id) }
                                Verb(title: store.text("action.delete")) {
                                    guard let spaceId = store.spaceId else { return }
                                    store.perform(.deleteComponent(spaceId: spaceId, componentId: component.id))
                                }
                            }
                            ForEach(store.categories(in: store.spaceId ?? "", componentId: component.id)) { category in
                                HStack {
                                    ClayRow(title: category.name, subtitle: store.text("taxonomy.category"))
                                    Verb(title: store.text("action.delete")) {
                                        guard let spaceId = store.spaceId else { return }
                                        store.perform(.deleteCategory(spaceId: spaceId, categoryId: category.id))
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                .padding(28)
            }
        }
        .sheet(isPresented: $addingComponent) { NameSheet(title: store.text("taxonomy.addComponent")) { name in
            guard let spaceId = store.spaceId else { return false }
            store.perform(.createComponent(spaceId: spaceId, name: name, description: ""))
            return store.lastError == nil
        }}
        .sheet(item: $categoryComponent) { target in
            NameSheet(title: store.text("taxonomy.addCategory")) { name in
                guard let spaceId = store.spaceId else { return false }
                store.perform(.createCategory(spaceId: spaceId, componentId: target.id, name: name, description: ""))
                return store.lastError == nil
            }
        }
    }

    private var components: [ActivityComponent] { store.components(in: store.spaceId ?? "") }
}

struct CategoryTarget: Identifiable {
    var id: String
}

struct NameSheet: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    var title: String
    var save: (String) -> Bool
    @State private var name = ""

    var body: some View {
        SheetFrame(title: title, saveTitle: store.text("action.create"), saveEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
            if save(name) { dismiss() }
        } content: {
            ClayField(label: store.text("common.name"), text: $name)
        }
    }
}
