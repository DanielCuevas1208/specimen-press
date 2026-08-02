import Foundation
import XCTest
@testable import SpecimenPress

final class SpecimenPressTests: XCTestCase {
    func testBundledFixtureExposesKnownMetricsAndCoverage() throws {
        let font = try DemoFont.load()

        XCTAssertEqual(font.familyName, "Specimen Press")
        XCTAssertEqual(font.metrics.unitsPerEm, 1_000)
        XCTAssertEqual(font.metrics.ascender, 800)
        XCTAssertEqual(font.metrics.descender, -200)
        XCTAssertEqual(font.metrics.lineGap, 200)
        XCTAssertEqual(font.metrics.numberOfGlyphs, 28)
        XCTAssertEqual(font.characterMap.count, 27)
        XCTAssertEqual(font.glyphIndex(for: "A"), 2)
        XCTAssertEqual(font.glyphIndex(for: " "), 1)
        XCTAssertNil(font.glyphIndex(for: "a"))
    }

    func testSimpleGlyphOutlineAndMetricAreDecoded() throws {
        let font = try DemoFont.load()
        let glyph = try XCTUnwrap(font.glyph(for: "A"))
        let outline = try XCTUnwrap(glyph.outline)

        XCTAssertEqual(glyph.index, 2)
        XCTAssertEqual(glyph.metrics.advanceWidth, 600)
        XCTAssertEqual(glyph.metrics.leftSideBearing, 0)
        XCTAssertFalse(outline.isEmpty)
        XCTAssertGreaterThan(outline.contours.count, 1)
        XCTAssertTrue(glyph.svgPath.hasPrefix("M "))
        XCTAssertTrue(glyph.svgPath.contains(" Z"))
    }

    func testSummaryReportsStructuredCoverageRanges() throws {
        let summary = try DemoFont.load().summary

        XCTAssertEqual(summary.familyName, "Specimen Press")
        XCTAssertEqual(summary.mappedCodePointCount, 27)
        XCTAssertEqual(summary.glyphsWithOutlines, 27)
        XCTAssertEqual(summary.unicodeCoverage, [
            UnicodeRange(start: 32, end: 32),
            UnicodeRange(start: 65, end: 90)
        ])
    }

    func testRendererIsDeterministicAndIncludesInspectionLabels() throws {
        let font = try DemoFont.load()
        let renderer = SpecimenRenderer()
        let first = renderer.render(font: font)
        let second = renderer.render(font: font)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("TRUE TYPE / OUTLINE INSPECTION"))
        XCTAssertTrue(first.contains("ASCENDER 800"))
        XCTAssertTrue(first.contains("BASELINE 0"))
        XCTAssertTrue(first.contains("DESCENDER -200"))
        XCTAssertTrue(first.contains("Glyph A / 2"))
        XCTAssertTrue(first.contains("<path"))
    }

    func testInvalidDataFailsWithUsefulError() {
        XCTAssertThrowsError(try TrueTypeFont(data: Data([0, 1, 2, 3]))) { error in
            XCTAssertEqual(error as? FontError, .invalidSignature)
        }
    }
}
