import AppKit
import CoreGraphics
import XCTest

final class TextLayoutTests: XCTestCase {
    private func line(_ text: String, x: CGFloat, y: CGFloat, charWidth: CGFloat = 10) -> TextLine {
        TextLine(text: text, box: CGRect(x: x, y: y, width: CGFloat(text.count) * charWidth, height: 16))
    }

    func testRebuildsIndentationForCode() {
        let lines = [
            line("func greet() {", x: 10, y: 0),
            line("print(\"hi\")", x: 50, y: 22),
            line("}", x: 10, y: 44),
        ]
        XCTAssertEqual(TextLayout.arrange(lines, keepIndent: true), "func greet() {\n    print(\"hi\")\n}")
    }

    func testBlankLineForBigGap() {
        let lines = [line("First paragraph", x: 0, y: 0), line("Second one", x: 0, y: 60)]
        XCTAssertEqual(TextLayout.arrange(lines, keepIndent: false), "First paragraph\n\nSecond one")
    }

    func testPiecesOnOneRowStayTogether() {
        let lines = [line("Name", x: 0, y: 0), line("Price", x: 200, y: 2)]
        let text = TextLayout.arrange(lines, keepIndent: false)
        XCTAssertTrue(text.hasPrefix("Name "))
        XCTAssertTrue(text.hasSuffix("Price"))
        XCTAssertFalse(text.contains("\n"))
    }

    func testJoinsWrappedLines() {
        let text = """
            The quick brown fox jumps over the lazy dog and then it keeps on run-
            ning far away from the farm because it wants to see the wide world
            out there.

            Next paragraph
            """
        XCTAssertEqual(
            TextLayout.joinBrokenLines(text),
            "The quick brown fox jumps over the lazy dog and then it keeps on running far away from the farm because it wants to see the wide world out there.\n\nNext paragraph")
    }

    func testKeepsListItemsApart() {
        let text = "Things to bring for the trip this weekend please:\n• Tent\n• Water bottle\n1. First step"
        XCTAssertEqual(TextLayout.joinBrokenLines(text), text)
    }
}

final class ClassifierTests: XCTestCase {
    private func kind(_ text: String, barcodes: [String] = [], tableShare: Double = 0) -> CaptureKind {
        Classifier.kind(
            text: text, tableShare: tableShare, barcodes: barcodes,
            detected: Detected.scan(text, findDates: false))
    }

    func testCode() {
        XCTAssertEqual(kind("""
            func load(id: String) async throws -> User {
                let data = try await api.get("/users/\\(id)")
                return try decoder.decode(User.self, from: data)
            }
            """), .code)
        XCTAssertEqual(kind("""
            def total(items):
                return sum(i.price for i in items)
            """), .code)
    }

    func testLog() {
        XCTAssertEqual(kind("""
            2026-11-25 10:02:11 INFO Server started on port 8080
            2026-11-25 10:02:15 ERROR Connection refused: db.local:5432
            2026-11-25 10:02:16 WARN Retrying in 5s
            """), .log)
        XCTAssertEqual(kind("""
            Traceback (most recent call last):
              File "app.py", line 12, in <module>
                main()
            ValueError: invalid literal for int()
            """), .log)
    }

    func testProseIsPlain() {
        XCTAssertEqual(kind("""
            We are moving the team meeting to next week. Please bring your notes.
            Lunch will be provided for everyone who comes along.
            """), .plain)
    }

    func testContact() {
        XCTAssertEqual(kind("Jane Appleseed\nHead of Design\njane@example.com\n+1 (415) 555-0132"), .contact)
    }

    func testQR() {
        XCTAssertEqual(kind("Scan me", barcodes: ["https://example.com"]), .qr)
    }

    func testTable() {
        XCTAssertEqual(kind("a b c", tableShare: 0.9), .table)
    }
}

final class FormatTests: XCTestCase {
    let table = [["Name", "Price"], ["Tea", "2.50"], ["Cake, big", "4"]]

    func testCSVQuotesCommas() {
        XCTAssertEqual(PasteFormat.csv.apply(to: "", table: table, kind: .table), "Name,Price\nTea,2.50\n\"Cake, big\",4")
    }

    func testMarkdownTable() {
        XCTAssertEqual(
            PasteFormat.markdown.apply(to: "", table: table, kind: .table),
            "| Name | Price |\n| --- | --- |\n| Tea | 2.50 |\n| Cake, big | 4 |")
    }

    func testJSONObjects() {
        let json = PasteFormat.json.apply(to: "", table: table, kind: .table)
        XCTAssertTrue(json.contains("\"Name\" : \"Tea\""))
    }

    func testSnakeCase() {
        XCTAssertEqual(PasteFormat.snakeCase.apply(to: "User Name\nfirstName", table: nil, kind: .plain), "user_name\nfirst_name")
    }

    func testCSVFromSpacedColumns() {
        XCTAssertEqual(PasteFormat.csv.apply(to: "a   b\nc\td", table: nil, kind: .plain), "a,b\nc,d")
    }
}

final class DetectedTests: XCTestCase {
    func testFindsLinksEmailsPhones() {
        let found = Detected.scan("Visit https://apple.com or mail hi@example.com, call 020 7946 0958", findDates: false)
        XCTAssertEqual(found.links.first?.host(), "apple.com")
        XCTAssertEqual(found.emails, ["hi@example.com"])
        XCTAssertFalse(found.phones.isEmpty)
    }

    func testFindsDates() {
        let found = Detected.scan("Team lunch tomorrow at 1pm in the cafe", findDates: true)
        XCTAssertEqual(found.dates.count, 1)
        XCTAssertEqual(found.dates.first?.line, "Team lunch tomorrow at 1pm in the cafe")
    }
}

/// Runs Apple's real text reader on images drawn here.
final class TextReaderTests: XCTestCase {
    private func image(_ lines: [String], font: NSFont, size: CGSize = CGSize(width: 900, height: 300)) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        for (index, line) in lines.enumerated() {
            let y = size.height - 40 - CGFloat(index) * font.pointSize * 1.5
            (line as NSString).draw(at: NSPoint(x: 20, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    func testReadsCodeWithIndentation() async throws {
        let font = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
        let cg = image(["func greet(name: String) {", "    print(\"Hello\")", "}"], font: font)
        let capture = Capture.make(from: try await TextReader.read(cg))
        XCTAssertEqual(capture.kind, .code)
        let lines = capture.layoutText.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3, capture.layoutText)
        XCTAssertTrue(lines[1].hasPrefix("    print"), capture.layoutText)
    }

    func testReadsProseAndJoinsLines() async throws {
        let font = NSFont.systemFont(ofSize: 22)
        let cg = image([
            "Reading text from the screen should feel like magic,",
            "and the lines that only wrapped should come back as",
            "one sentence when you paste them.",
        ], font: font)
        let capture = Capture.make(from: try await TextReader.read(cg))
        XCTAssertEqual(capture.kind, .plain)
        XCTAssertFalse(capture.joinedText.contains("\n"), capture.joinedText)
        XCTAssertTrue(capture.joinedText.contains("magic, and the lines"), capture.joinedText)
    }
}
