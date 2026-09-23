import PDFKit
import UIKit

/// Turns the pages a user added (scans, photos, PDFs, text, cover sheet) into one US Letter PDF.
enum PDFBuilder {
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func build(pages: [DraftPage], cover: CoverSheet) async throws -> (Data, Int) {
        var count = 0
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            if cover.enabled {
                ctx.beginPage(); count += 1
                drawCover(cover)
            }
            for page in pages {
                switch page.source {
                case .scan, .photo:
                    if let image = page.image { ctx.beginPage(); count += 1; drawImage(image) }
                case .text(let text):
                    ctx.beginPage(); count += 1
                    drawText(text)
                case .file(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let document = PDFDocument(url: url) {
                        for index in 0..<document.pageCount {
                            guard let pdfPage = document.page(at: index) else { continue }
                            ctx.beginPage(); count += 1
                            drawPDFPage(pdfPage, in: ctx.cgContext)
                        }
                    } else if let image = UIImage(contentsOfFile: url.path) {
                        ctx.beginPage(); count += 1
                        drawImage(image)
                    }
                }
            }
        }
        return (data, max(count, 1))
    }

    private static func drawImage(_ image: UIImage) {
        let area = pageRect.insetBy(dx: 18, dy: 18)
        let scale = min(area.width / image.size.width, area.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height))
    }

    private static func drawPDFPage(_ page: PDFPage, in context: CGContext) {
        let box = page.bounds(for: .mediaBox)
        let scale = min(pageRect.width / box.width, pageRect.height / box.height)
        context.saveGState()
        context.translateBy(x: (pageRect.width - box.width * scale) / 2, y: pageRect.height - (pageRect.height - box.height * scale) / 2)
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }

    private static func drawText(_ text: String) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Georgia", size: 13) ?? .systemFont(ofSize: 13),
            .foregroundColor: UIColor.black,
            .paragraphStyle: style
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: pageRect.insetBy(dx: 64, dy: 72))
    }

    private static func drawCover(_ cover: CoverSheet) {
        let title: [NSAttributedString.Key: Any] = [.font: UIFont(name: "Georgia-Bold", size: 44) ?? .boldSystemFont(ofSize: 44)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont(name: "Georgia", size: 15) ?? .systemFont(ofSize: 15)]
        NSAttributedString(string: "FAX", attributes: title).draw(at: CGPoint(x: 64, y: 72))
        if cover.urgent {
            NSAttributedString(string: "URGENT", attributes: [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.red])
                .draw(at: CGPoint(x: 64, y: 130))
        }
        let lines = [
            "From: \(cover.from)",
            "To: \(cover.to)",
            "Subject: \(cover.subject)",
            "Date: \(Date.now.formatted(date: .long, time: .shortened))"
        ]
        for (i, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: body).draw(at: CGPoint(x: 64, y: 170 + CGFloat(i) * 28))
        }
        NSAttributedString(string: cover.note, attributes: body).draw(in: CGRect(x: 64, y: 300, width: 484, height: 420))
    }
}
