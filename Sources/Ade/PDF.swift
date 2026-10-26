import AppKit
import CoreGraphics
import CoreText
import Foundation
import AdeCore

enum PDFDrawError: Error {
    case background
    case context
}

func renderPDF(database: Database, pages: [PlannedPage]) throws -> Data {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw PDFDrawError.context }
    var first = CGRect(x: 0, y: 0, width: pages.first?.width ?? 612, height: pages.first?.height ?? 792)
    guard let context = CGContext(consumer: consumer, mediaBox: &first, nil) else { throw PDFDrawError.context }
    if pages.isEmpty {
        beginPage(context, width: 612, height: 792)
        context.endPDFPage()
    }
    for page in pages {
        beginPage(context, width: page.width, height: page.height)
        if page.backgroundAssetId != nil {
            try drawBackground(database: database, page: page, context: context)
        }
        for item in page.items {
            switch item {
            case .text(let text):
                drawText(text, pageHeight: page.height, context: context)
            case .image(let image):
                drawImage(database: database, image: image, pageHeight: page.height, context: context)
            }
        }
        context.endPDFPage()
    }
    context.closePDF()
    return data as Data
}

private func beginPage(_ context: CGContext, width: Double, height: Double) {
    var media = CGRect(x: 0, y: 0, width: width, height: height)
    let box = NSData(bytes: &media, length: MemoryLayout<CGRect>.size)
    let info = NSDictionary(dictionary: [kCGPDFContextMediaBox: box])
    context.beginPDFPage(info)
}

private func drawBackground(database: Database, page: PlannedPage, context: CGContext) throws {
    guard let assetId = page.backgroundAssetId,
          let asset = database.assets.first(where: { $0.id == assetId && $0.deletedAt == nil && $0.mime == .pdf }),
          let bytes = Data(base64Encoded: asset.dataBase64, options: .ignoreUnknownCharacters) else {
        throw PDFDrawError.background
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    try bytes.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { throw PDFDrawError.background }
    let index = min(max(page.backgroundPageIndex + 1, 1), document.numberOfPages)
    guard let pdfPage = document.page(at: index) else { throw PDFDrawError.background }
    let box = pdfPage.getBoxRect(.cropBox)
    context.saveGState()
    context.scaleBy(x: page.width / max(box.width, 1), y: page.height / max(box.height, 1))
    context.translateBy(x: -box.origin.x, y: -box.origin.y)
    context.drawPDFPage(pdfPage)
    context.restoreGState()
}

private func drawText(_ text: PlannedText, pageHeight: Double, context: CGContext) {
    let safe = pdfSafe(text.text)
    let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(text.fontSize), nil)
    let attributed = NSAttributedString(string: safe, attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let used = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    var x = text.x
    if text.align == .center { x += max(0, (text.width - used) / 2) }
    if text.align == .right { x += max(0, text.width - used) }
    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: pageHeight - text.y - text.fontSize)
    CTLineDraw(line, context)
    context.restoreGState()
}

private func drawImage(database: Database, image: PlannedImage, pageHeight: Double, context: CGContext) {
    guard let asset = database.assets.first(where: { $0.id == image.assetId && $0.deletedAt == nil }),
          let bytes = Data(base64Encoded: asset.dataBase64, options: .ignoreUnknownCharacters),
          let provider = CGDataProvider(data: bytes as CFData) else { return }
    let cg: CGImage?
    switch asset.mime {
    case .jpeg:
        cg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    case .png:
        cg = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    case .pdf:
        cg = nil
    }
    guard let cg else { return }
    let rect = CGRect(x: image.x, y: pageHeight - image.y - image.height, width: image.width, height: image.height)
    context.draw(cg, in: rect)
}

private func pdfSafe(_ text: String) -> String {
    var result = ""
    for character in text {
        let scalars = Array(character.unicodeScalars)
        if scalars.count == 1, let value = scalars.first?.value, value >= 32, value <= 255 {
            result.append(character)
        } else {
            result.append("?")
        }
    }
    return result
}
