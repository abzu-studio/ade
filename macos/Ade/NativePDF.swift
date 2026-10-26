import AppKit
import CoreText
import PDFKit

struct DocumentOptions {
  var eventId: String
  var personId = ""
  var periodId = ""
  var revisionId: String
}
enum NativePDF {
  static let placeholders = [
    "space.name", "space.timeZone", "event.name", "event.date", "event.time", "event.status",
    "event.component", "event.category", "person.name", "person.email", "period.name",
    "attendance.present", "attendance.absent", "attendance.percentage", "revision.id",
  ]
  static func interpolate(_ text: String, values: [String: String]) throws -> String {
    let regex = try NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
    var result = text
    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
      let key = (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(
        in: .whitespaces)
      guard let value = values[key], let range = Range(match.range, in: result) else {
        throw RuleError("Variable desconocida: \(key)")
      }
      result.replaceSubrange(range, with: value)
    }
    return result
  }
  static func defaultTemplate() -> DocumentTemplate {
    var t = DocumentTemplate()
    t.name = "Informe de participación"
    t.blocks = [
      TemplateBlock(type: .text, text: "{{space.name}}\n{{event.name}}", size: 24),
      TemplateBlock(
        type: .columns,
        left: "Fecha: {{event.date}}\nHora: {{event.time}}\nZona: {{space.timeZone}}",
        right:
          "Componente: {{event.component}}\nCategoría: {{event.category}}\nEstado: {{event.status}}"
      ),
      TemplateBlock(
        type: .text,
        text:
          "Porcentaje = presentes / (presentes + ausentes). Se excluyen pendientes, excusados, cancelados, borradores, eventos que no cuentan y personas fuera de la lista. Sin denominador: sin datos.",
        size: 10), .make(.participants),
    ]
    return t
  }
  enum Draw {
    case text(CTLine, Double, Double, Double)
    case image(CGImage, CGRect)
  }
  static func generate(space: Space, template: DocumentTemplate, options o: DocumentOptions) throws
    -> Data
  {
    try Rules.validate(space)
    guard let event = space.event(o.eventId) else { throw RuleError("Selecciona un evento") }
    let person = space.person(o.personId)
    let period = space.periods.first { $0.id == o.periodId }
    try require(
      o.personId.isEmpty || (person != nil && event.participantIds.contains(o.personId)),
      "La persona debe estar en el evento")
    try require(o.periodId.isEmpty || period != nil, "Período inexistente")
    let filter =
      o.periodId.isEmpty ? ReportFilter(eventId: event.id) : ReportFilter(periodId: o.periodId)
    let index = ParticipationIndex(space)
    let result = try person.map { try index.participation(person: $0.id, filter: filter) }
    let values: [String: String] = [
      "space.name": space.name, "space.timeZone": space.timeZone, "event.name": event.name,
      "event.date": event.date, "event.time": event.time, "event.status": event.status.rawValue,
      "event.component": space.components.first { $0.id == event.componentId }?.name ?? "",
      "event.category": space.categories.first { $0.id == event.categoryId }?.name ?? "",
      "person.name": person?.name ?? "", "person.email": person?.email ?? "",
      "period.name": period?.name ?? "",
      "attendance.present": result.map { String($0.present) } ?? "",
      "attendance.absent": result.map { String($0.absent) } ?? "",
      "attendance.percentage": result.map {
        $0.percentage == nil ? "Sin datos / No data" : $0.formatted
      } ?? "", "revision.id": o.revisionId,
    ]
    let top = template.marginTop
    let bottom = 792 - template.marginBottom
    try require(
      (24...240).contains(top) && (40...240).contains(template.marginBottom), "Márgenes inválidos")
    var pages: [[Draw]] = [[]]
    var y = top
    func newPage() {
      pages.append([])
      y = top
    }
    func room(_ height: Double) { if y + height > bottom { newPage() } }
    func lines(_ text: String, size: Double, width: Double) -> [CTLine] {
      let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
      let attributed = NSAttributedString(
        string: text.isEmpty ? " " : text,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
            gray: 0.1, alpha: 1),
        ])
      let typesetter = CTTypesetterCreateWithAttributedString(attributed)
      var result: [CTLine] = []
      var start = 0
      while start < attributed.length {
        let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, width))
        result.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
        start += count
      }
      return result
    }
    func text(_ string: String, size: Double = 11) {
      for line in lines(string, size: size, width: 516) {
        room(size * 1.45)
        pages[pages.count - 1].append(.text(line, 48, y, size))
        y += size * 1.45
      }
      y += 10
    }
    func columns(_ left: String, _ right: String) {
      let a = lines(left, size: 11, width: 248)
      let b = lines(right, size: 11, width: 248)
      for i in 0..<max(a.count, b.count) {
        room(16)
        if i < a.count { pages[pages.count - 1].append(.text(a[i], 48, y, 11)) }
        if i < b.count { pages[pages.count - 1].append(.text(b[i], 316, y, 11)) }
        y += 16
      }
      y += 10
    }
    for block in template.blocks {
      switch block.type {
      case .text: text(try interpolate(block.text ?? "", values: values), size: block.size ?? 12)
      case .columns:
        columns(
          try interpolate(block.left ?? "", values: values),
          try interpolate(block.right ?? "", values: values))
      case .pageBreak: newPage()
      case .participants:
        text("Participantes / Participants", size: 15)
        for id in (o.personId.isEmpty ? event.participantIds : [o.personId]) {
          guard let p = space.person(id) else { continue }
          let r = try index.participation(person: id, filter: filter)
          columns(
            p.name + (p.email.isEmpty ? "" : "\n" + p.email),
            "\(space.record(event.id,id)?.status.rawValue ?? "pending") · \(r.present)/\(r.denominator) · \(r.formatted)"
          )
        }
      case .image:
        guard let uri = block.data, let comma = uri.firstIndex(of: ","),
          let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw RuleError("No se pudo leer la imagen") }
        let w = min(516, block.width ?? 240)
        let ratio = Double(image.height) / Double(image.width)
        let scale = min(1, (bottom - top) / (w * ratio))
        let width = w * scale
        let height = w * ratio * scale
        room(height)
        pages[pages.count - 1].append(
          .image(image, CGRect(x: 48, y: 792 - y - height, width: width, height: height)))
        y += height + 10
      }
    }
    var background: CGPDFDocument?
    if let base64 = template.backgroundPDF {
      guard let data = Data(base64Encoded: base64),
        let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider),
        !doc.isEncrypted, doc.numberOfPages > 0
      else { throw RuleError("PDF de fondo inválido o protegido") }
      background = doc
      while pages.count < doc.numberOfPages { pages.append([]) }
    }
    let data = NSMutableData()
    var media = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: data),
      let context = CGContext(
        consumer: consumer, mediaBox: &media,
        [
          kCGPDFContextTitle: template.name, kCGPDFContextCreator: "Adê Native",
          kCGPDFContextSubject: "Revision \(o.revisionId)",
        ] as CFDictionary)
    else { throw RuleError("No se pudo crear el PDF") }
    for (index, page) in pages.enumerated() {
      context.beginPDFPage(nil)
      if let background, let bg = background.page(at: min(index + 1, background.numberOfPages)) {
        context.saveGState()
        context.concatenate(
          bg.getDrawingTransform(.mediaBox, rect: media, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(bg)
        context.restoreGState()
      }
      for draw in page {
        switch draw {
        case .text(let line, let x, let top, let size):
          context.textMatrix = .identity
          context.textPosition = CGPoint(x: x, y: 792 - top - size)
          CTLineDraw(line, context)
        case .image(let image, let rect): context.draw(image, in: rect)
        }
      }
      let footer = "Adê · \(o.revisionId) · \(index+1) / \(pages.count)"
      let line = lines(footer, size: 8, width: 516)[0]
      context.textPosition = CGPoint(x: 48, y: 22)
      CTLineDraw(line, context)
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }
}
