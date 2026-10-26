import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PDFPreview: NSViewRepresentable {
  var data: Data
  func makeNSView(context: Context) -> PDFView {
    let v = PDFView()
    v.setAccessibilityIdentifier("pdf-preview")
    v.autoScales = true
    v.displayMode = .singlePageContinuous
    return v
  }
  func updateNSView(_ view: PDFView, context: Context) {
    if context.coordinator.data != data {
      view.document = PDFDocument(data: data)
      context.coordinator.data = data
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  final class Coordinator { var data: Data? }
}
struct DocumentsView: View {
  @Environment(AppModel.self) private var m
  @State private var selected: String?
  @State private var draft: DocumentTemplate?
  @State private var eventId = ""
  @State private var personId = ""
  @State private var periodId = ""
  @State private var pdf: Data?
  @State private var generatedRevision = ""
  @State private var generating = false
  @State private var requestID = UUID()
  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: m.t("Documentos", "Documents"), subtitle: m.space?.name ?? "") {
        Button(m.t("Nueva plantilla", "New template")) { draft = NativePDF.defaultTemplate() }
          .accessibilityIdentifier("document-new-template")
          .buttonStyle(ActionLink()).disabled(!m.canEdit)
      }
      HStack(spacing: 0) {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(m.space?.templates ?? []) { t in
              PaperSelectionRow(selected: selected == t.id, action: { selected = t.id }) {
                VStack(alignment: .leading, spacing: 5) {
                  Text(t.name.uppercased()).font(.custom(Enki.condensed, size: 22))
                  Text("\(t.blocks.count) " + m.t("bloques", "blocks")).font(.caption)
                    .foregroundStyle(
                      .secondary)
                }
              }.accessibilityIdentifier("template-" + t.id)
            }
          }
        }.frame(width: 225)
        Rectangle().fill(Enki.rule).frame(width: 0.5)
        VStack(alignment: .leading, spacing: 14) {
          if let t = m.space?.templates.first(where: { $0.id == selected }), let s = m.space {
            HStack {
              Text(t.name).font(.custom(Enki.condensed, size: 28))
              Spacer()
              Button(m.t("Editar plantilla", "Edit template")) { draft = t }.disabled(!m.canEdit)
              PaperMenu {
                Button(m.t("Eliminar plantilla", "Delete template"), role: .destructive) {
                  Task { _ = await m.edit(.delete(.templates, t.id), label: "Eliminar plantilla") }
                }
              } label: {
                Image(systemName: "ellipsis")
              }.disabled(!m.canEdit).frame(width: 25)
            }
            HStack {
              PaperPicker(
                m.t("Evento", "Event"), selection: $eventId,
                options: [PaperOption("", "—")] + (s.events).map { PaperOption($0.id, $0.name) }
              ).accessibilityIdentifier("document-event").onChange(of: eventId) {
                personId = ""
                invalidatePreview()
              }
              PaperPicker(
                m.t("Persona", "Person"), selection: $personId,
                options: [PaperOption("", m.t("Lista completa", "Full roster"))]
                  + ((s.event(eventId)?.participantIds ?? []).compactMap { s.person($0) }).map {
                    PaperOption($0.id, $0.name)
                  }
              ).onChange(of: personId) { invalidatePreview() }
            }
            HStack {
              PaperPicker(
                m.t("Resultados", "Results"), selection: $periodId,
                options: [PaperOption("", m.t("Este evento", "This event"))]
                  + (s.periods).map { PaperOption($0.id, $0.name) }
              ).onChange(of: periodId) { invalidatePreview() }
              Button(m.t("Generar vista previa", "Generate preview")) { generate(s, t) }.disabled(
                eventId.isEmpty || generating || m.branch?.conflicted == true)
              Button(m.t("Guardar PDF…", "Save PDF…")) {
                if let pdf {
                  do { try Panels.save(pdf, name: "Ade-documento.pdf", type: .pdf) } catch {
                    m.error = error.localizedDescription
                  }
                }
              }.disabled(pdf == nil)
            }
            if generating { ProgressView() }
            if let pdf {
              Text(m.t("Revisión de origen: ", "Source revision: ") + generatedRevision).font(
                .caption
              ).foregroundStyle(.secondary).textSelection(.enabled)
              PDFPreview(data: pdf).frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(PaperArrival(trigger: generatedRevision))
            } else {
              EmptyState(
                title: m.t("Documento por generar", "Document to generate"),
                detail: m.t(
                  "Selecciona un evento y genera el documento con sus datos reales.",
                  "Select an event and generate a document using its real data."),
                symbol: "doc.text")
            }
          } else {
            EmptyState(
              title: m.t("Plantillas de documentos", "Document templates"),
              detail: m.t(
                "Crea o selecciona una plantilla para generar un PDF.",
                "Create or select a template to generate a PDF."), symbol: "doc.text")
          }
        }.padding(24).frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
      }
    }.sheet(item: $draft) {
      TemplateEditor(
        value: $0,
        onSaved: {
          selected = $0
          invalidatePreview()
        })
    }
    .onAppear {
      if !m.documentEvent.isEmpty {
        eventId = m.documentEvent
        selected = m.space?.templates.first?.id
        m.documentEvent = ""
      }
    }
    .onChange(of: selected) { invalidatePreview() }
    .onChange(of: m.selectedSpace) {
      selected = nil
      eventId = ""
      personId = ""
      periodId = ""
      invalidatePreview()
    }
  }
  private func invalidatePreview() {
    requestID = UUID()
    pdf = nil
    generating = false
  }
  private func generate(_ s: Space, _ t: DocumentTemplate) {
    let request = UUID()
    requestID = request
    generating = true
    let options = DocumentOptions(
      eventId: eventId, personId: personId, periodId: periodId,
      revisionId: m.branch?.heads.first ?? "")
    Task {
      do {
        let data = try await Task.detached {
          try NativePDF.generate(space: s, template: t, options: options)
        }.value
        guard requestID == request else { return }
        pdf = data
        generatedRevision = options.revisionId
      } catch { if requestID == request { m.error = error.localizedDescription } }
      if requestID == request { generating = false }
    }
  }
}
struct TemplateEditor: View {
  @Environment(AppModel.self) private var m
  @State private var template: DocumentTemplate
  var onSaved: (String) -> Void
  init(value: DocumentTemplate, onSaved: @escaping (String) -> Void) {
    _template = State(initialValue: value)
    self.onSaved = onSaved
  }
  var body: some View {
    SheetFrame(
      title: m.t("Plantilla de documento", "Document template"),
      save: {
        let ok = await m.edit(.template(template), label: "Guardar plantilla")
        if ok { onSaved(template.id) }
        return ok
      }
    ) {
      VStack(alignment: .leading, spacing: 18) {
        PaperInput(m.t("Nombre de plantilla", "Template name")) {
          TextField(m.t("Nombre de plantilla", "Template name"), text: $template.name)
        }.textFieldStyle(PaperFieldStyle())
        HStack {
          PaperInput(m.t("Margen superior", "Top margin")) {
            TextField(
              m.t("Margen superior", "Top margin"), value: $template.marginTop, format: .number)
          }
          PaperInput(m.t("Margen inferior", "Bottom margin")) {
            TextField(
              m.t("Margen inferior", "Bottom margin"), value: $template.marginBottom,
              format: .number)
          }
        }.textFieldStyle(PaperFieldStyle())
        HStack {
          Button(m.t("Importar PDF de fondo…", "Import background PDF…")) {
            do {
              if let data = try Panels.open(types: [.pdf]) {
                guard let doc = PDFDocument(data: data), !doc.isLocked, doc.pageCount > 0 else {
                  throw RuleError("PDF inválido o protegido")
                }
                template.backgroundPDF = data.base64EncodedString()
              }
            } catch { m.error = error.localizedDescription }
          }
          if template.backgroundPDF != nil {
            Text(m.t("Fondo incluido", "Background included")).font(.caption)
            Button(m.t("Quitar", "Remove")) { template.backgroundPDF = nil }
          }
        }
        PaperDisclosure(m.t("Variables disponibles", "Available variables")) {
          Text(NativePDF.placeholders.map { "{{" + $0 + "}}" }.joined(separator: "\n")).font(
            .system(.caption, design: .monospaced)
          ).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach($template.blocks) { $block in
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text(blockTitle(block.type)).font(.custom(Enki.mono, size: 11))
              Spacer()
              Button {
                move(block.id, -1)
              } label: {
                Image(systemName: "arrow.up")
              }.help(m.t("Subir bloque", "Move block up"))
              Button {
                move(block.id, 1)
              } label: {
                Image(systemName: "arrow.down")
              }.help(m.t("Bajar bloque", "Move block down"))
              Button(role: .destructive) {
                template.blocks.removeAll { $0.id == block.id }
              } label: {
                Image(systemName: "trash")
              }.help(m.t("Quitar bloque", "Remove block"))
            }
            switch block.type {
            case .text:
              PaperTextEditor(text: Binding(get: { block.text ?? "" }, set: { block.text = $0 }))
                .font(
                  .body
                ).frame(height: 100).border(Enki.rule)
              HStack {
                MicroLabel(text: m.t("Tamaño", "Size"))
                Button("−") { block.size = max(8, (block.size ?? 12) - 1) }.accessibilityLabel(
                  m.t("Reducir tamaño", "Decrease size"))
                Text("\(Int(block.size ?? 12)) pt").font(.custom(Enki.mono, size: 12))
                Button("+") { block.size = min(36, (block.size ?? 12) + 1) }.accessibilityLabel(
                  m.t("Aumentar tamaño", "Increase size"))
              }
            case .columns:
              HStack {
                PaperTextEditor(text: Binding(get: { block.left ?? "" }, set: { block.left = $0 }))
                PaperTextEditor(
                  text: Binding(get: { block.right ?? "" }, set: { block.right = $0 }))
              }.font(.body).frame(height: 130).border(Enki.rule)
            case .image:
              HStack {
                Button(m.t("Elegir imagen…", "Choose image…")) {
                  do {
                    if let data = try Panels.open(types: [.png, .jpeg]) {
                      guard NSImage(data: data) != nil else { throw RuleError("Imagen inválida") }
                      let mime = data.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? "png" : "jpeg"
                      block.data = "data:image/\(mime);base64," + data.base64EncodedString()
                    }
                  } catch { m.error = error.localizedDescription }
                }
                Text(
                  (block.data ?? "").isEmpty
                    ? m.t("Sin imagen", "No image") : m.t("Imagen incluida", "Image included"))
                PaperInput(m.t("Ancho (pt)", "Width (pt)")) {
                  TextField(
                    m.t("Ancho (pt)", "Width (pt)"),
                    value: Binding(get: { block.width ?? 240 }, set: { block.width = $0 }),
                    format: .number
                  )
                }.frame(width: 120)
              }
            case .participants:
              Text(
                m.t(
                  "Inserta la lista real del evento, estados y resultados calculados.",
                  "Inserts the event roster, recorded states and calculated results.")
              ).font(.caption)
            case .pageBreak:
              Text(m.t("Comienza una nueva página.", "Starts a new page.")).font(.caption)
            }
            Divider()
          }.padding(.vertical, 8)
        }
        PaperMenu(m.t("Añadir bloque", "Add block")) {
          ForEach(BlockKind.allCases, id: \.rawValue) { kind in
            Button(blockTitle(kind)) { template.blocks.append(.make(kind)) }
          }
        }
      }
    }
  }
  private func move(_ id: String, _ offset: Int) {
    guard let i = template.blocks.firstIndex(where: { $0.id == id }),
      template.blocks.indices.contains(i + offset)
    else { return }
    template.blocks.swapAt(i, i + offset)
  }
  private func blockTitle(_ kind: BlockKind) -> String {
    switch kind {
    case .text: m.t("Texto", "Text")
    case .columns: m.t("Dos columnas", "Two columns")
    case .image: m.t("Imagen", "Image")
    case .participants: m.t("Participantes", "Participants")
    case .pageBreak: m.t("Salto de página", "Page break")
    }
  }
}
