import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        SpacePage(title: store.text("history.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.text("history.warning"))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber)
                    if revisions.isEmpty {
                        Text(store.text("history.empty")).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
                    }
                    ForEach(Array(revisions.indices), id: \.self) { index in
                        let revision = revisions[index]
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.revisionText(revision))
                                    .font(AdeFont.medium(15))
                                    .foregroundStyle(Clay.umber)
                                Text(formatWhen(revision.at, locale: store.locale))
                                    .font(AdeFont.kicker(11))
                                    .foregroundStyle(Clay.umber.opacity(0.75))
                                if index > cursor {
                                    Text(String(index))
                                        .font(AdeFont.kicker(11))
                                        .foregroundStyle(Clay.ink)
                                }
                            }
                            Spacer()
                            if index == cursor {
                                Stamp(title: store.text("history.current"), kind: .pressed)
                            } else {
                                Verb(title: store.text("history.restore")) {
                                    guard let spaceId = store.spaceId else { return }
                                    store.perform(.restoreRevision(spaceId: spaceId, revisionId: revision.id), announce: .none)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
                    }
                }
                .padding(28)
            }
        }
    }

    private var history: SpaceHistory? {
        store.database.histories.first { $0.spaceId == store.spaceId }
    }

    private var cursor: Int { history?.cursor ?? -1 }

    private var revisions: [Revision] {
        guard let history else { return [] }
        return history.revisionIds.compactMap { id in store.database.revisions.first { $0.id == id } }
    }
}

struct ConflictsScreen: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        SpacePage(title: store.text("conflicts.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.text("conflicts.help"))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber)
                    if pending.isEmpty && resolved.isEmpty {
                        Text(store.text("conflicts.empty")).font(AdeFont.body(15)).foregroundStyle(Clay.umber)
                    }
                    if !pending.isEmpty {
                        Text(store.text("conflicts.pending").uppercased())
                            .font(AdeFont.kicker(11))
                            .foregroundStyle(Clay.ink)
                        ForEach(pending) { conflict in
                            conflictCard(conflict, pending: true)
                        }
                    }
                    if !resolved.isEmpty {
                        Text(store.text("conflicts.resolved").uppercased())
                            .font(AdeFont.kicker(11))
                            .foregroundStyle(Clay.ink)
                            .padding(.top, 8)
                        ForEach(resolved) { conflict in
                            conflictCard(conflict, pending: false)
                        }
                    }
                }
                .padding(28)
            }
        }
    }

    private var pending: [ConflictRecord] { store.pendingConflicts(in: store.spaceId ?? "") }
    private var resolved: [ConflictRecord] {
        store.database.conflicts.filter { $0.spaceId == store.spaceId && $0.resolution != .pending }
    }

    private func conflictCard(_ conflict: ConflictRecord, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(conflict.entityType.rawValue) · \(conflict.key)")
                .font(AdeFont.medium(15))
                .foregroundStyle(Clay.umber)
            Text(store.text("conflicts.local").uppercased())
                .font(AdeFont.kicker(11))
                .foregroundStyle(Clay.ink)
            Text(jsonPreview(conflict.local))
                .font(AdeFont.kicker(11))
                .foregroundStyle(Clay.umber)
                .textSelection(.enabled)
            Text(store.text("conflicts.remote").uppercased())
                .font(AdeFont.kicker(11))
                .foregroundStyle(Clay.ink)
            if conflict.remoteDeleted {
                Text(store.text("conflicts.remoteDeleted")).font(AdeFont.body(13)).foregroundStyle(Clay.umber)
            } else {
                Text(jsonPreview(conflict.remote))
                    .font(AdeFont.kicker(11))
                    .foregroundStyle(Clay.umber)
                    .textSelection(.enabled)
            }
            if pending {
                HStack(spacing: 12) {
                    Verb(title: store.text("conflicts.keepLocal")) { resolve(conflict, .keptLocal) }
                    Verb(title: store.text("conflicts.keepRemote")) { resolve(conflict, .keptRemote) }
                    Verb(title: store.text("conflicts.keepBoth")) { resolve(conflict, .keptBoth) }
                }
            } else {
                Stamp(title: store.text(resolutionKey(conflict.resolution)))
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
    }

    private func resolve(_ conflict: ConflictRecord, _ resolution: ConflictResolution) {
        guard let spaceId = store.spaceId else { return }
        store.perform(.resolveConflict(spaceId: spaceId, conflictId: conflict.id, resolution: resolution))
    }

    private func resolutionKey(_ resolution: ConflictResolution) -> String {
        switch resolution {
        case .pending: return "conflicts.pending"
        case .keptLocal: return "conflicts.keepLocal"
        case .keptRemote: return "conflicts.keepRemote"
        case .keptBoth: return "conflicts.keepBoth"
        }
    }
}

struct DataScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var actor = ""

    var body: some View {
        SpacePage(title: store.text("data.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ClayField(label: store.text("data.actor"), text: $actor)
                    Verb(title: store.text("action.save")) {
                        store.perform(.setActorName(actor))
                    }
                    Text(store.text("data.backupHelp"))
                        .font(AdeFont.body(14))
                        .foregroundStyle(Clay.umber)
                    Verb(title: store.text("data.backup")) { store.exportBackup() }
                    Text(store.text("data.syncHelp"))
                        .font(AdeFont.body(14))
                        .foregroundStyle(Clay.umber)
                    Verb(title: store.text("data.sync")) { store.exportSpace() }
                    Text(store.text("data.replaceHelp"))
                        .font(AdeFont.body(14))
                        .foregroundStyle(Clay.umber)
                    Verb(title: store.text("data.import")) { store.importFile() }
                }
                .padding(28)
                .frame(maxWidth: 640, alignment: .leading)
            }
        }
        .onAppear { actor = store.database.actor.name }
        .onChange(of: store.database.actor.name) { _, name in actor = name }
    }
}

struct RulesScreen: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        SpacePage(title: store.text("rules.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    rule(store.text("rules.attendanceTitle"), store.text("rules.attendanceBody"))
                    Text(attendanceFormula)
                        .font(AdeFont.kicker(13))
                        .foregroundStyle(Clay.ink)
                    rule(store.text("rules.volunteerTitle"), store.text("rules.volunteerBody"))
                    Text(store.text("volunteers.recentDays", ["days": String(VolunteerWeights.recentDays)]))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber)
                    Text(store.text("volunteers.presentCap", ["cap": String(VolunteerWeights.attendancePresentCap)]))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber)
                    weight("completed", VolunteerWeights.completed)
                    weight("recentCompleted", VolunteerWeights.recentCompleted)
                    weight("sameComponentCompleted", VolunteerWeights.sameComponentCompleted)
                    weight("selected", VolunteerWeights.selected)
                    weight("priorInterested", VolunteerWeights.priorInterested)
                    weight("interestedNow", VolunteerWeights.interestedNow)
                    weight("declined", VolunteerWeights.declined)
                    weight("absent", VolunteerWeights.absent)
                    weight("attendancePresent", VolunteerWeights.attendancePresent)
                    rule(store.text("rules.statesTitle"), store.text("rules.statesBody"))
                    rule(store.text("rules.collabTitle"), store.text("rules.collabBody"))
                    rule(store.text("rules.docsTitle"), store.text("rules.docsBody"))
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    private func rule(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(AdeFont.kicker(11))
                .tracking(1.2)
                .foregroundStyle(Clay.ink)
            Text(body)
                .font(AdeFont.body(15))
                .foregroundStyle(Clay.umber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func weight(_ code: String, _ points: Int) -> some View {
        Text(store.text("volunteers.factors.\(code)", ["count": "1", "points": String(points)]))
            .font(AdeFont.kicker(12))
            .foregroundStyle(Clay.umber)
    }
}
