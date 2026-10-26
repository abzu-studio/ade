import SwiftUI

struct DocumentsScreen: View {
    @EnvironmentObject private var store: AdeStore
    @State private var message: String?

    var body: some View {
        SpacePage(title: store.text("documents.title")) {
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Verb(title: store.text("documents.add")) { createBlank() }
                        Verb(title: store.text("documents.preset")) { createPreset() }
                    }
                    .padding(.horizontal, 12)
                    Verb(title: store.text("documents.upload")) { store.chooseAsset() }
                        .padding(.horizontal, 12)
                    if templates.isEmpty {
                        Text(store.text("documents.empty"))
                            .font(AdeFont.body(14))
                            .foregroundStyle(Clay.umber)
                            .padding(16)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(templates) { template in
                                ClayRow(title: template.name, subtitle: template.pageSize.rawValue, selected: store.templateId == template.id) {
                                    store.templateId = template.id
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 300)
                if let template = templates.first(where: { $0.id == store.templateId }) {
                    TemplateEditor(template: template, message: $message)
                } else {
                    Text(store.text("documents.empty"))
                        .font(AdeFont.body(15))
                        .foregroundStyle(Clay.umber)
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var spaceId: String { store.spaceId ?? "" }
    private var templates: [DocumentTemplate] { store.templates(in: spaceId) }

    private func createBlank() {
        guard let spaceId = store.spaceId else { return }
        store.perform(.createTemplate(spaceId: spaceId, name: store.text("documents.add"), description: "", pageSize: .letter, backgroundAssetId: nil, elements: []))
        store.templateId = newestTemplate(in: spaceId)
    }

    private func createPreset() {
        guard let spaceId = store.spaceId else { return }
        store.perform(.createTemplate(
            spaceId: spaceId,
            name: store.text("documents.preset"),
            description: "",
            pageSize: .letter,
            backgroundAssetId: nil,
            elements: attendanceSummaryElements()
        ))
        store.templateId = newestTemplate(in: spaceId)
    }

    private func newestTemplate(in spaceId: String) -> String? {
        store.database.templates.filter { $0.spaceId == spaceId }.max { $0.createdAt < $1.createdAt }?.id
    }
}

struct TemplateEditor: View {
    @EnvironmentObject private var store: AdeStore
    var template: DocumentTemplate
    @Binding var message: String?
    @State private var name = ""
    @State private var details = ""
    @State private var pageSize: PageSize = .letter
    @State private var backgroundId = ""
    @State private var elements: [EditorElement] = []
    @State private var periodId = ""
    @State private var eventId = ""
    @State private var groupId = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ClayField(label: store.text("common.name"), text: $name)
                ClayField(label: store.text("common.description"), text: $details, axis: .vertical)
                Picker(store.text("documents.pageSize"), selection: $pageSize) {
                    Text("Letter").tag(PageSize.letter)
                    Text("A4").tag(PageSize.a4)
                }
                Picker(store.text("documents.background"), selection: $backgroundId) {
                    Text(store.text("common.none")).tag("")
                    ForEach(pdfAssets) { asset in
                        Text(asset.name).tag(asset.id)
                    }
                }
                HStack(spacing: 12) {
                    Verb(title: store.text("documents.addText")) { elements.append(EditorElement.text()) }
                    Verb(title: store.text("documents.addColumns")) { elements.append(EditorElement.columns()) }
                    Verb(title: store.text("documents.addImage"), enabled: !imageAssets.isEmpty) {
                        elements.append(EditorElement.image(assetId: imageAssets.first?.id ?? ""))
                    }
                }
                ForEach($elements) { $element in
                    elementEditor($element)
                }
                Text(store.text("documents.context").uppercased())
                    .font(AdeFont.kicker(11))
                    .foregroundStyle(Clay.ink)
                    .padding(.top, 8)
                Picker(store.text("nav.periods"), selection: $periodId) {
                    Text(store.text("common.none")).tag("")
                    ForEach(store.periods(in: template.spaceId)) { period in
                        Text(period.name).tag(period.id)
                    }
                }
                Picker(store.text("nav.events"), selection: $eventId) {
                    Text(store.text("common.none")).tag("")
                    ForEach(store.events(in: template.spaceId)) { event in
                        Text(event.title).tag(event.id)
                    }
                }
                Picker(store.text("nav.groups"), selection: $groupId) {
                    Text(store.text("common.none")).tag("")
                    ForEach(store.groups(in: template.spaceId)) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                HStack(spacing: 14) {
                    Verb(title: store.text("action.save")) { save() }
                    Verb(title: store.text("documents.generate")) { generate() }
                    Verb(title: store.text("action.delete")) {
                        store.perform(.deleteTemplate(spaceId: template.spaceId, templateId: template.id))
                        if store.lastError == nil { store.templateId = nil }
                    }
                }
                if let message {
                    Text(message).font(AdeFont.body(13)).foregroundStyle(Clay.ink)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
        .onChange(of: template.id) { _, _ in load() }
        .onChange(of: template.updatedAt) { _, _ in load() }
    }

    private var pdfAssets: [Asset] { store.assets(in: template.spaceId).filter { $0.mime == .pdf } }
    private var imageAssets: [Asset] { store.assets(in: template.spaceId).filter { $0.mime == .png || $0.mime == .jpeg } }

    private func elementEditor(_ element: Binding<EditorElement>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(element.wrappedValue.kind.rawValue.uppercased())
                    .font(AdeFont.kicker(11))
                    .foregroundStyle(Clay.ink)
                Spacer()
                Verb(title: store.text("documents.remove")) {
                    elements.removeAll { $0.id == element.wrappedValue.id }
                }
            }
            HStack {
                ClayField(label: store.text("documents.x"), text: element.x)
                ClayField(label: store.text("documents.y"), text: element.y)
                ClayField(label: store.text("documents.width"), text: element.width)
                ClayField(label: store.text("documents.height"), text: element.height)
            }
            switch element.wrappedValue.kind {
            case .text:
                ClayField(label: store.text("documents.literal"), text: element.text)
                ClayField(label: store.text("documents.fontSize"), text: element.fontSize)
                Picker(store.text("documents.binding"), selection: element.binding) {
                    Text(store.text("binding.none")).tag(Optional<TextBinding>.none)
                    ForEach(TextBinding.allCases, id: \.self) { binding in
                        Text(store.text("binding.\(binding.rawValue)")).tag(Optional(binding))
                    }
                }
                Picker(store.text("documents.align"), selection: element.align) {
                    Text(store.text("documents.left")).tag(TextAlign.left)
                    Text(store.text("documents.center")).tag(TextAlign.center)
                    Text(store.text("documents.right")).tag(TextAlign.right)
                }
            case .image:
                Picker(store.text("documents.asset"), selection: element.assetId) {
                    ForEach(imageAssets) { asset in
                        Text(asset.name).tag(asset.id)
                    }
                }
            case .columns:
                ClayField(label: store.text("documents.columnsCount"), text: element.columns)
                ClayField(label: store.text("documents.gap"), text: element.gap)
                ClayField(label: store.text("documents.fontSize"), text: element.fontSize)
                Picker(store.text("documents.listBinding"), selection: element.listBinding) {
                    ForEach(ListBinding.allCases, id: \.self) { binding in
                        Text(store.text("list.\(binding.rawValue)")).tag(binding)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Clay.tint).frame(height: 1) }
    }

    private func load() {
        name = template.name
        details = template.description
        pageSize = template.pageSize
        backgroundId = template.backgroundAssetId ?? ""
        elements = template.elements.map { EditorElement(element: $0) }
        if periodId.isEmpty { periodId = store.periods(in: template.spaceId).first?.id ?? "" }
    }

    private func drafts() -> [ElementDraft]? {
        var result: [ElementDraft] = []
        for element in elements {
            guard let x = Double(element.x), let y = Double(element.y), let width = Double(element.width), let height = Double(element.height) else { return nil }
            switch element.kind {
            case .text:
                guard let fontSize = Double(element.fontSize) else { return nil }
                result.append(.text(TextElementDraft(id: element.existingId, x: x, y: y, width: width, height: height, text: element.text, binding: element.binding, fontSize: fontSize, align: element.align)))
            case .image:
                result.append(.image(ImageElementDraft(id: element.existingId, x: x, y: y, width: width, height: height, assetId: element.assetId)))
            case .columns:
                guard let fontSize = Double(element.fontSize), let columns = Int(element.columns), let gap = Double(element.gap) else { return nil }
                result.append(.columns(ColumnsElementDraft(id: element.existingId, x: x, y: y, width: width, height: height, columns: columns, gap: gap, binding: element.listBinding, fontSize: fontSize)))
            }
        }
        return result
    }

    private func save() {
        guard let drafts = drafts() else {
            store.lastError = store.text("error.INVALID_TEMPLATE")
            return
        }
        store.perform(.updateTemplate(
            spaceId: template.spaceId,
            templateId: template.id,
            name: name,
            description: details,
            pageSize: pageSize,
            backgroundAssetId: backgroundId.isEmpty ? nil : backgroundId,
            elements: drafts
        ))
    }

    private func generate() {
        save()
        guard store.lastError == nil,
              let current = store.database.templates.first(where: { $0.id == template.id }) else { return }
        let context = TemplateDataContext(
            spaceId: template.spaceId,
            periodId: periodId.isEmpty ? nil : periodId,
            eventId: eventId.isEmpty ? nil : eventId,
            groupId: groupId.isEmpty ? nil : groupId,
            generatedAt: isoTimestamp()
        )
        switch planDocument(store.database, current, context, labels: store.documentLabels()) {
        case .ok(let pages):
            do {
                let data = try renderPDF(database: store.database, pages: pages)
                message = store.text("documents.generated", ["count": String(pages.count)])
                store.savePanel(data: data, name: "\(current.name).pdf", type: .pdf)
            } catch {
                store.lastError = store.text("error.ASSET_NOT_FOUND")
            }
        case .err(let error):
            store.lastError = store.errorText(error)
        }
    }
}

struct EditorElement: Identifiable {
    enum Kind: String { case text, image, columns }
    var id = UUID().uuidString
    var existingId: String?
    var kind: Kind
    var x: String
    var y: String
    var width: String
    var height: String
    var text: String = ""
    var fontSize: String = "12"
    var columns: String = "1"
    var gap: String = "8"
    var align: TextAlign = .left
    var binding: TextBinding?
    var listBinding: ListBinding = .periodParticipation
    var assetId: String = ""

    static func text() -> EditorElement {
        EditorElement(kind: .text, x: "48", y: "48", width: "200", height: "24", text: "", fontSize: "14")
    }

    static func columns() -> EditorElement {
        EditorElement(kind: .columns, x: "48", y: "120", width: "500", height: "400", fontSize: "11", columns: "2", gap: "16")
    }

    static func image(assetId: String) -> EditorElement {
        EditorElement(kind: .image, x: "48", y: "48", width: "120", height: "80", assetId: assetId)
    }

    init(element: TemplateElement) {
        switch element {
        case .text(let value):
            id = value.id
            existingId = value.id
            kind = .text
            x = Self.number(value.x)
            y = Self.number(value.y)
            width = Self.number(value.width)
            height = Self.number(value.height)
            text = value.text
            fontSize = Self.number(value.fontSize)
            align = value.align
            binding = value.binding
        case .image(let value):
            id = value.id
            existingId = value.id
            kind = .image
            x = Self.number(value.x)
            y = Self.number(value.y)
            width = Self.number(value.width)
            height = Self.number(value.height)
            assetId = value.assetId
        case .columns(let value):
            id = value.id
            existingId = value.id
            kind = .columns
            x = Self.number(value.x)
            y = Self.number(value.y)
            width = Self.number(value.width)
            height = Self.number(value.height)
            columns = String(value.columns)
            gap = Self.number(value.gap)
            fontSize = Self.number(value.fontSize)
            listBinding = value.binding
        }
    }

    init(id: String = UUID().uuidString, existingId: String? = nil, kind: Kind, x: String, y: String, width: String, height: String, text: String = "", fontSize: String = "12", columns: String = "1", gap: String = "8", align: TextAlign = .left, binding: TextBinding? = nil, listBinding: ListBinding = .periodParticipation, assetId: String = "") {
        self.id = id
        self.existingId = existingId
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
        self.fontSize = fontSize
        self.columns = columns
        self.gap = gap
        self.align = align
        self.binding = binding
        self.listBinding = listBinding
        self.assetId = assetId
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
