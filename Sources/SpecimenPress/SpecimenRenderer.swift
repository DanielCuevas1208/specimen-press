import Foundation

public struct SpecimenRenderer {
    public struct Configuration {
        public let width: Int
        public let margin: Int
        public let columns: Int
        public let cellWidth: Int
        public let cellHeight: Int
        public let title: String
        public let sampleText: String

        public init(
            width: Int = 1_080,
            margin: Int = 48,
            columns: Int = 10,
            cellWidth: Int = 96,
            cellHeight: Int = 124,
            title: String = "Specimen Press",
            sampleText: String = "SPECIMEN PRESS / METRICS / GLYPH OUTLINES"
        ) {
            self.width = width
            self.margin = margin
            self.columns = columns
            self.cellWidth = cellWidth
            self.cellHeight = cellHeight
            self.title = title
            self.sampleText = sampleText
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func render(font: TrueTypeFont, sampleText: String? = nil) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let gridRows = (alphabet.count + configuration.columns - 1) / configuration.columns
        let headerHeight = 210
        let height = headerHeight + gridRows * configuration.cellHeight + configuration.margin
        let sample = sampleText ?? configuration.sampleText
        let metrics = font.metrics
        let metricHeight = max(1.0, Double(metrics.ascender - metrics.descender))
        let metricScale = 104.0 / metricHeight
        let baselineY = 144.0
        let ascenderY = baselineY - Double(metrics.ascender) * metricScale
        let descenderY = baselineY - Double(metrics.descender) * metricScale

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 \(configuration.width) \(height)" role="img" aria-labelledby="title description">
          <title id="title">\(escape(configuration.title))</title>
          <desc id="description">A TrueType glyph specimen for \(escape(font.familyName)).</desc>
          <style>
            .paper { fill: #f5f1e8; }
            .ink { fill: #20231f; }
            .muted { fill: #726b5e; }
            .rule { stroke: #b9ae9c; stroke-width: 1; }
            .accent { stroke: #c75c3d; stroke-width: 1.5; }
            .cell { fill: none; stroke: #d8cebd; stroke-width: 1; }
          </style>
          <rect class="paper" width="100%" height="100%"/>
          <text class="muted" x="\(configuration.margin)" y="34" font-family="sans-serif" font-size="12" letter-spacing="2">TRUE TYPE / OUTLINE INSPECTION</text>
          <text class="ink" x="\(configuration.margin)" y="76" font-family="sans-serif" font-size="34" font-weight="700">\(escape(configuration.title))</text>
          <text class="muted" x="\(configuration.margin)" y="100" font-family="sans-serif" font-size="14">\(escape(font.familyName)) / \(font.glyphs.count) glyphs / \(font.characterMap.count) mapped code points</text>
          <line class="rule" x1="\(configuration.margin)" y1="\(format(baselineY))" x2="\(configuration.width - configuration.margin)" y2="\(format(baselineY))"/>
          <line class="accent" x1="\(configuration.margin)" y1="\(format(ascenderY))" x2="\(configuration.width - configuration.margin)" y2="\(format(ascenderY))"/>
          <line class="accent" x1="\(configuration.margin)" y1="\(format(descenderY))" x2="\(configuration.width - configuration.margin)" y2="\(format(descenderY))"/>
          <text class="muted" x="\(configuration.margin)" y="\(format(ascenderY - 6))" font-family="sans-serif" font-size="11">ASCENDER \(metrics.ascender)</text>
          <text class="muted" x="\(configuration.margin)" y="\(format(baselineY - 6))" font-family="sans-serif" font-size="11">BASELINE 0</text>
          <text class="muted" x="\(configuration.margin)" y="\(format(descenderY + 16))" font-family="sans-serif" font-size="11">DESCENDER \(metrics.descender)</text>
          \(renderSample(sample, font: font, baseline: baselineY + 42))
          <text class="muted" x="\(configuration.margin)" y="\(headerHeight - 18)" font-family="sans-serif" font-size="11">GLYPH COVERAGE / A-Z</text>
        """

        for (offset, character) in alphabet.enumerated() {
            let column = offset % configuration.columns
            let row = offset / configuration.columns
            let x = configuration.margin + column * configuration.cellWidth
            let y = headerHeight + row * configuration.cellHeight
            svg += renderCell(character, font: font, x: x, y: y)
        }

        svg += "  </svg>\n"
        return svg
    }

    private func renderSample(_ text: String, font: TrueTypeFont, baseline: Double) -> String {
        var result = "<g aria-label='Sample text' fill='#20231f'>"
        let scale = min(0.055, 54.0 / max(1.0, Double(font.metrics.unitsPerEm)))
        var x = Double(configuration.margin)
        for character in text {
            let scalar = character.unicodeScalars.first
            let index = scalar.flatMap { font.glyphIndex(for: $0) } ?? 0
            guard Int(index) < font.glyphs.count else { continue }
            let glyph = font.glyphs[Int(index)]
            if let outline = glyph.outline, !outline.isEmpty {
                let path = outline.svgPath()
                result += "<path d='\(path)' transform='translate(\(format(x)) \(format(baseline))) scale(\(format(scale)) \(format(-scale)))'/>"
            }
            x += Double(glyph.metrics.advanceWidth) * scale
            if x > Double(configuration.width - configuration.margin) { break }
        }
        return result + "</g>\n"
    }

    private func renderCell(_ character: Character, font: TrueTypeFont, x: Int, y: Int) -> String {
        let scalar = character.unicodeScalars.first
        let index = scalar.flatMap { font.glyphIndex(for: $0) } ?? 0
        let glyph = Int(index) < font.glyphs.count ? font.glyphs[Int(index)] : font.glyphs[0]
        let bounds = glyph.outline?.bounds ?? GlyphBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
        let usableWidth = Double(configuration.cellWidth - 24)
        let usableHeight = Double(configuration.cellHeight - 42)
        let scale = min(usableWidth / max(1.0, bounds.width), usableHeight / max(1.0, bounds.height))
        let boundedScale = min(scale, 0.12)
        let center = Double(x) + Double(configuration.cellWidth) / 2
        let glyphCenter = (bounds.minX + bounds.maxX) / 2
        let baseline = Double(y + configuration.cellHeight - 24)
        let translateX = center - glyphCenter * boundedScale
        let path = glyph.svgPath

        var result = "  <g aria-label='Glyph \(escape(String(character))) / \(index)'>\n"
        result += "    <rect class='cell' x='\(x)' y='\(y)' width='\(configuration.cellWidth)' height='\(configuration.cellHeight)'/>\n"
        if !path.isEmpty {
            result += "    <path class='ink' d='\(path)' transform='translate(\(format(translateX)) \(format(baseline))) scale(\(format(boundedScale)) \(format(-boundedScale)))'/>\n"
        }
        result += "    <text class='muted' x='\(x + 10)' y='\(y + configuration.cellHeight - 8)' font-family='sans-serif' font-size='12'>\(escape(String(character))) / \(index)</text>\n"
        return result + "  </g>\n"
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\u{22}", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
