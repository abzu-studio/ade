import SwiftUI

struct Verb: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(AdeFont.kicker(12))
                .tracking(0.7)
                .underline(true, color: hover && enabled ? Clay.umber : Clay.ink)
                .foregroundStyle(hover && enabled ? Clay.umber : Clay.ink)
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
    }
}

struct Stamp: View {
    enum Kind { case plain, pressed, scheduled, completed, cancelled }

    var title: String
    var kind: Kind = .plain
    var action: (() -> Void)?

    var body: some View {
        let label = Text(title.uppercased())
            .font(AdeFont.kicker(11))
            .tracking(0.8)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(Rectangle().stroke(border, lineWidth: 1))
            .strikethrough(kind == .cancelled, color: Clay.umber)
            .opacity(kind == .cancelled ? 0.75 : 1)
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    private var foreground: Color {
        switch kind {
        case .pressed, .scheduled, .completed: return Clay.cream
        case .plain, .cancelled: return Clay.umber
        }
    }

    private var background: Color {
        switch kind {
        case .pressed, .scheduled: return Clay.ink
        case .completed: return Clay.umber
        case .plain, .cancelled: return kind == .cancelled ? .clear : Clay.cream
        }
    }

    private var border: Color {
        switch kind {
        case .pressed, .scheduled: return Clay.ink
        case .completed, .plain, .cancelled: return Clay.umber
        }
    }
}

struct ClayField: View {
    var label: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(AdeFont.kicker(11))
                .tracking(1.2)
                .foregroundStyle(Clay.ink)
            TextField(label, text: $text, axis: axis)
                .textFieldStyle(.plain)
                .font(AdeFont.body(15))
                .foregroundStyle(Clay.umber)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Clay.umber).frame(height: 1) }
        }
    }
}

struct ClayRow: View {
    var title: String
    var subtitle: String?
    var selected: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let body = HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AdeFont.medium(15))
                    .foregroundStyle(Clay.umber)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AdeFont.kicker(11))
                        .foregroundStyle(Clay.umber.opacity(0.72))
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Clay.tintWash : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { body }.buttonStyle(.plain)
        } else {
            body
        }
    }
}

struct StorageBanner: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        HStack(spacing: 16) {
            Text(store.text("app.storageError"))
                .font(AdeFont.body(14))
                .foregroundStyle(Clay.umber)
            Spacer()
            Verb(title: store.text("app.reset")) { store.resetStorage() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Clay.tint)
    }
}

struct ErrorBanner: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        if let lastError = store.lastError {
            HStack(spacing: 16) {
                Text(lastError)
                    .font(AdeFont.body(14))
                    .foregroundStyle(Clay.ink)
                Spacer()
                Verb(title: store.text("action.close")) { store.dismissError() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Clay.cream)
            .overlay(alignment: .bottom) { Rectangle().fill(Clay.ink).frame(height: 1) }
        }
    }
}

struct PageHeader: View {
    @EnvironmentObject private var store: AdeStore
    var title: String

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let name = store.space?.name {
                    Text(name.uppercased())
                        .font(AdeFont.kicker(11))
                        .tracking(1.4)
                        .foregroundStyle(Clay.ink)
                }
                Text(title.uppercased())
                    .font(AdeFont.display(42))
                    .tracking(1.6)
                    .foregroundStyle(Clay.umber)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                Verb(title: store.text("action.undo"), enabled: store.canUndoSpace) { store.undo() }
                Verb(title: store.text("action.redo"), enabled: store.canRedoSpace) { store.redo() }
                Picker(store.text("common.language"), selection: localeBinding) {
                    Text(store.text("common.english")).tag(AdeLocale.en)
                    Text(store.text("common.spanish")).tag(AdeLocale.es)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var localeBinding: Binding<AdeLocale> {
        Binding(
            get: { store.locale },
            set: { store.perform(.setLocale($0), announce: .none) }
        )
    }
}

struct SpacePage<Content: View>: View {
    @EnvironmentObject private var store: AdeStore
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.storageError { StorageBanner() }
            ErrorBanner()
            PageHeader(title: title)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Clay.paper)
    }
}

struct Sidebar: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { store.goHome() } label: {
                HStack(spacing: 8) {
                    Image(nsImage: Marks.menuSmall)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                    Text("ADÊ")
                        .font(AdeFont.display(28))
                        .tracking(1.4)
                        .foregroundStyle(Clay.umber)
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .buttonStyle(.plain)
            if let space = store.space {
                Text(space.name.uppercased())
                    .font(AdeFont.display(20))
                    .tracking(0.8)
                    .foregroundStyle(Clay.umber)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(AdeRoute.allCases) { route in
                            navLink(route)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                }
            } else {
                Text(store.text("nav.spaces").uppercased())
                    .font(AdeFont.kicker(11))
                    .tracking(1.3)
                    .foregroundStyle(Clay.ink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sortedSpaces) { space in
                            Button { store.open(space.id) } label: {
                                Text(space.name)
                                    .font(AdeFont.medium(14))
                                    .foregroundStyle(Clay.umber)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Clay.cream)
    }

    private var sortedSpaces: [Space] {
        store.database.spaces.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func navLink(_ route: AdeRoute) -> some View {
        let count = route == .conflicts ? store.pendingConflicts(in: store.spaceId ?? "").count : 0
        let title = count > 0 ? "\(store.text(route.messageKey)) (\(count))" : store.text(route.messageKey)
        let active = store.route == route
        return Button { store.go(route) } label: {
            Text(title)
                .font(AdeFont.medium(14))
                .foregroundStyle(Clay.umber)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Clay.tint : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 196, ideal: 228, max: 280)
        } detail: {
            Group {
                if store.space == nil {
                    HomeScreen()
                } else {
                    SpaceScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Clay.paper)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Clay.paper)
        .preferredColorScheme(.light)
        .sheet(isPresented: $store.presentNewSpace) { NewSpaceSheet() }
        .alert(store.text("data.replaceTitle"), isPresented: $store.confirmBackup) {
            Button(store.text("action.import")) { store.commitBackup() }
            Button(store.text("action.cancel"), role: .cancel) { store.cancelBackup() }
        } message: {
            Text(store.text("data.replaceHelp"))
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast.uppercased())
                    .font(AdeFont.kicker(12))
                    .tracking(0.8)
                    .foregroundStyle(Clay.cream)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Clay.umber)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: store.toast)
    }
}

struct SpaceScreen: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        switch store.route {
        case .overview: OverviewScreen()
        case .people: PeopleScreen()
        case .groups: GroupsScreen()
        case .periods: PeriodsScreen()
        case .components: ComponentsScreen()
        case .events: EventsScreen()
        case .participation: ParticipationScreen()
        case .documents: DocumentsScreen()
        case .history: HistoryScreen()
        case .conflicts: ConflictsScreen()
        case .data: DataScreen()
        case .rules: RulesScreen()
        }
    }
}

struct SheetFrame<Content: View>: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    var title: String
    var saveTitle: String
    var saveEnabled: Bool = true
    var onSave: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title.uppercased())
                .font(AdeFont.display(32))
                .tracking(1.2)
                .foregroundStyle(Clay.umber)
            content()
            HStack {
                Spacer()
                Verb(title: store.text("action.cancel")) { dismiss() }
                Verb(title: saveTitle, enabled: saveEnabled, action: onSave)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .background(Clay.cream)
    }
}
