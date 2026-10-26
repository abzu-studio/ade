import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var store: AdeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.storageError { StorageBanner() }
            ErrorBanner()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 16) {
                        Image(nsImage: Marks.menu)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ADÊ")
                                .font(AdeFont.display(64))
                                .tracking(2)
                                .foregroundStyle(Clay.umber)
                            Text(store.text("app.tagline"))
                                .font(AdeFont.body(16))
                                .foregroundStyle(Clay.umber)
                        }
                    }
                    HStack(spacing: 18) {
                        Verb(title: store.text("spaces.create")) { store.presentNewSpace = true }
                        Verb(title: store.text("spaces.demo")) { store.perform(.loadDemo) }
                    }
                    Text(store.text("spaces.demoHelp"))
                        .font(AdeFont.body(13))
                        .foregroundStyle(Clay.umber.opacity(0.8))
                    Text(store.text("spaces.title").uppercased())
                        .font(AdeFont.kicker(11))
                        .tracking(1.4)
                        .foregroundStyle(Clay.ink)
                        .padding(.top, 8)
                    if spaces.isEmpty {
                        Text(store.text("spaces.empty"))
                            .font(AdeFont.body(15))
                            .foregroundStyle(Clay.umber)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(spaces) { space in
                                HStack {
                                    ClayRow(title: space.name, subtitle: nil) { store.open(space.id) }
                                    Verb(title: store.text("action.open")) { store.open(space.id) }
                                        .padding(.trailing, 8)
                                }
                            }
                        }
                    }
                }
                .padding(32)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Clay.paper)
    }

    private var spaces: [Space] {
        store.database.spaces.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct NewSpaceSheet: View {
    @EnvironmentObject private var store: AdeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        SheetFrame(title: store.text("spaces.create"), saveTitle: store.text("action.create"), saveEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
            store.perform(.createSpace(name: name))
            if store.lastError == nil { dismiss() }
        } content: {
            ClayField(label: store.text("common.name"), text: $name)
        }
    }
}
