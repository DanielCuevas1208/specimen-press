import Foundation

public struct FontMetrics: Codable, Equatable {
    public let unitsPerEm: UInt16
    public let ascender: Int16
    public let descender: Int16
    public let lineGap: Int16
    public let numberOfGlyphs: Int
    public let numberOfHorizontalMetrics: Int

    public init(
        unitsPerEm: UInt16,
        ascender: Int16,
        descender: Int16,
        lineGap: Int16,
        numberOfGlyphs: Int,
        numberOfHorizontalMetrics: Int
    ) {
        self.unitsPerEm = unitsPerEm
        self.ascender = ascender
        self.descender = descender
        self.lineGap = lineGap
        self.numberOfGlyphs = numberOfGlyphs
        self.numberOfHorizontalMetrics = numberOfHorizontalMetrics
    }
}

public struct UnicodeRange: Codable, Equatable {
    public let start: UInt32
    public let end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }
}

public struct FontSummary: Codable, Equatable {
    public let familyName: String
    public let outlineFormat: OutlineFormat
    public let metrics: FontMetrics
    public let mappedCodePointCount: Int
    public let glyphsWithOutlines: Int
    public let unicodeCoverage: [UnicodeRange]

    public init(
        familyName: String,
        outlineFormat: OutlineFormat,
        metrics: FontMetrics,
        mappedCodePointCount: Int,
        glyphsWithOutlines: Int,
        unicodeCoverage: [UnicodeRange]
    ) {
        self.familyName = familyName
        self.outlineFormat = outlineFormat
        self.metrics = metrics
        self.mappedCodePointCount = mappedCodePointCount
        self.glyphsWithOutlines = glyphsWithOutlines
        self.unicodeCoverage = unicodeCoverage
    }
}

public struct TrueTypeFont {
    public let familyName: String
    public let outlineFormat: OutlineFormat
    public let metrics: FontMetrics
    public let characterMap: [UInt32: UInt16]
    public let glyphs: [Glyph]

    public init(data: Data) throws {
        let reader = BinaryReader(data: data)
        let signature = try reader.uint32(at: 0)
        guard signature == 0x0001_0000 || signature == 0x4F54_544F else {
            throw FontError.invalidSignature
        }

        let numTables = Int(try reader.uint16(at: 4))
        guard numTables > 0 else { throw FontError.invalidValue("The table directory is empty.") }

        var tables: [String: TableRecord] = [:]
        for index in 0..<numTables {
            let recordOffset = 12 + index * 16
            let tag = try reader.tag(at: recordOffset)
            let offset = Int(try reader.uint32(at: recordOffset + 8))
            let length = Int(try reader.uint32(at: recordOffset + 12))
            guard length > 0 else { throw FontError.invalidTable(tag) }
            try reader.require(offset: offset, length: length)
            tables[tag] = TableRecord(offset: offset, length: length)
        }

        func table(_ tag: String) throws -> TableRecord {
            guard let record = tables[tag] else { throw FontError.missingTable(tag) }
            return record
        }

        let head = try table("head")
        let maxp = try table("maxp")
        let hhea = try table("hhea")
        let hmtx = try table("hmtx")
        let cmap = try table("cmap")

        guard head.length >= 54 else { throw FontError.invalidTable("head") }
        guard maxp.length >= 6 else { throw FontError.invalidTable("maxp") }
        guard hhea.length >= 36 else { throw FontError.invalidTable("hhea") }

        let unitsPerEm = try reader.uint16(at: head.offset + 18)
        guard unitsPerEm > 0 else { throw FontError.invalidValue("unitsPerEm must be positive.") }

        let numberOfGlyphs = Int(try reader.uint16(at: maxp.offset + 4))
        let numberOfHorizontalMetrics = Int(try reader.uint16(at: hhea.offset + 34))
        guard numberOfGlyphs > 0 else { throw FontError.invalidValue("The font has no glyphs.") }
        guard numberOfHorizontalMetrics > 0, numberOfHorizontalMetrics <= numberOfGlyphs else {
            throw FontError.invalidValue("The horizontal metric count is invalid.")
        }

        let ascender = try reader.int16(at: hhea.offset + 4)
        let descender = try reader.int16(at: hhea.offset + 6)
        let lineGap = try reader.int16(at: hhea.offset + 8)
        let parsedMetrics = FontMetrics(
            unitsPerEm: unitsPerEm,
            ascender: ascender,
            descender: descender,
            lineGap: lineGap,
            numberOfGlyphs: numberOfGlyphs,
            numberOfHorizontalMetrics: numberOfHorizontalMetrics
        )

        let glyphMetrics = try Self.readMetrics(
            reader: reader,
            table: hmtx,
            glyphCount: numberOfGlyphs,
            metricCount: numberOfHorizontalMetrics
        )
        let characterMap = try Self.readCharacterMap(reader: reader, table: cmap, glyphCount: numberOfGlyphs)

        let outlineFormat: OutlineFormat
        var parsedGlyphs: [Glyph] = []
        parsedGlyphs.reserveCapacity(numberOfGlyphs)

        if let glyf = tables["glyf"], let loca = tables["loca"] {
            let indexToLocFormat = try reader.int16(at: head.offset + 50)
            guard indexToLocFormat == 0 || indexToLocFormat == 1 else {
                throw FontError.invalidValue("indexToLocFormat must be 0 or 1.")
            }
            let offsets = try Self.readLoca(
                reader: reader,
                table: loca,
                glyphCount: numberOfGlyphs,
                format: indexToLocFormat
            )
            let decoder = GlyphDecoder(
                reader: reader,
                glyf: glyf,
                offsets: offsets,
                glyphCount: numberOfGlyphs
            )
            outlineFormat = .trueType
            for index in 0..<numberOfGlyphs {
                let outline = try decoder.outline(for: index)
                parsedGlyphs.append(
                    Glyph(index: UInt16(index), metrics: glyphMetrics[index], outline: outline)
                )
            }
        } else if let cff = tables["CFF "] {
            let decoder = try CFFDecoder(
                reader: reader,
                table: cff,
                isCFF2: false,
                glyphCount: numberOfGlyphs
            )
            outlineFormat = .cff
            for index in 0..<numberOfGlyphs {
                let outline = try decoder.outline(for: index)
                parsedGlyphs.append(
                    Glyph(index: UInt16(index), metrics: glyphMetrics[index], outline: outline)
                )
            }
        } else if let cff2 = tables["CFF2"] {
            let decoder = try CFFDecoder(
                reader: reader,
                table: cff2,
                isCFF2: true,
                glyphCount: numberOfGlyphs
            )
            outlineFormat = .cff2
            for index in 0..<numberOfGlyphs {
                let outline = try decoder.outline(for: index)
                parsedGlyphs.append(
                    Glyph(index: UInt16(index), metrics: glyphMetrics[index], outline: outline)
                )
            }
        } else {
            throw FontError.missingTable("glyf, CFF , or CFF2")
        }

        self.familyName = Self.readFamilyName(reader: reader, table: tables["name"]) ?? "Untitled font"
        self.outlineFormat = outlineFormat
        self.metrics = parsedMetrics
        self.characterMap = characterMap
        self.glyphs = parsedGlyphs
    }

    public static func load(from url: URL) throws -> TrueTypeFont {
        try TrueTypeFont(data: Data(contentsOf: url))
    }

    public func glyphIndex(for scalar: Unicode.Scalar) -> UInt16? {
        characterMap[scalar.value]
    }

    public func glyph(for scalar: Unicode.Scalar) -> Glyph? {
        guard let index = glyphIndex(for: scalar), Int(index) < glyphs.count else { return nil }
        return glyphs[Int(index)]
    }

    public var summary: FontSummary {
        let sortedCodePoints = characterMap.keys.sorted()
        var ranges: [UnicodeRange] = []
        if let first = sortedCodePoints.first {
            var start = first
            var previous = first
            for codePoint in sortedCodePoints.dropFirst() {
                if codePoint == previous + 1 {
                    previous = codePoint
                } else {
                    ranges.append(UnicodeRange(start: start, end: previous))
                    start = codePoint
                    previous = codePoint
                }
            }
            ranges.append(UnicodeRange(start: start, end: previous))
        }

        return FontSummary(
            familyName: familyName,
            outlineFormat: outlineFormat,
            metrics: metrics,
            mappedCodePointCount: characterMap.count,
            glyphsWithOutlines: glyphs.filter(\.hasOutline).count,
            unicodeCoverage: ranges
        )
    }
}

struct TableRecord {
    let offset: Int
    let length: Int
}

private extension TrueTypeFont {
    static func readMetrics(
        reader: BinaryReader,
        table: TableRecord,
        glyphCount: Int,
        metricCount: Int
    ) throws -> [GlyphMetrics] {
        let requiredLength = metricCount * 4 + (glyphCount - metricCount) * 2
        guard table.length >= requiredLength else { throw FontError.invalidTable("hmtx") }

        var result: [GlyphMetrics] = []
        result.reserveCapacity(glyphCount)
        var lastAdvance: UInt16 = 0
        for index in 0..<glyphCount {
            if index < metricCount {
                lastAdvance = try reader.uint16(at: table.offset + index * 4)
                let bearing = try reader.int16(at: table.offset + index * 4 + 2)
                result.append(GlyphMetrics(advanceWidth: lastAdvance, leftSideBearing: bearing))
            } else {
                let bearing = try reader.int16(at: table.offset + metricCount * 4 + (index - metricCount) * 2)
                result.append(GlyphMetrics(advanceWidth: lastAdvance, leftSideBearing: bearing))
            }
        }
        return result
    }

    static func readLoca(
        reader: BinaryReader,
        table: TableRecord,
        glyphCount: Int,
        format: Int16
    ) throws -> [Int] {
        let entrySize = format == 0 ? 2 : 4
        guard table.length >= (glyphCount + 1) * entrySize else { throw FontError.invalidTable("loca") }

        var result: [Int] = []
        result.reserveCapacity(glyphCount + 1)
        for index in 0...glyphCount {
            let offset = table.offset + index * entrySize
            let value: Int
            if format == 0 {
                value = Int(try reader.uint16(at: offset)) * 2
            } else {
                value = Int(try reader.uint32(at: offset))
            }
            if let previous = result.last, value < previous {
                throw FontError.invalidValue("loca offsets must be ordered.")
            }
            result.append(value)
        }
        return result
    }

    static func readCharacterMap(reader: BinaryReader, table: TableRecord, glyphCount: Int) throws -> [UInt32: UInt16] {
        guard table.length >= 4 else { throw FontError.invalidTable("cmap") }
        let numberOfSubtables = Int(try reader.uint16(at: table.offset + 2))
        guard table.length >= 4 + numberOfSubtables * 8 else { throw FontError.invalidTable("cmap") }

        var format12Offset: Int?
        var format4Offset: Int?
        for index in 0..<numberOfSubtables {
            let record = table.offset + 4 + index * 8
            let platform = try reader.uint16(at: record)
            let encoding = try reader.uint16(at: record + 2)
            let offset = table.offset + Int(try reader.uint32(at: record + 4))
            guard offset >= table.offset, offset < table.offset + table.length else {
                throw FontError.invalidTable("cmap")
            }
            let format = try reader.uint16(at: offset)
            if format == 12 && (platform == 0 || platform == 3) {
                format12Offset = offset
            } else if format == 4 && (platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10))) {
                format4Offset = offset
            }
        }

        if let offset = format12Offset {
            return try readFormat12(reader: reader, offset: offset, glyphCount: glyphCount)
        }
        if let offset = format4Offset {
            return try readFormat4(reader: reader, offset: offset, glyphCount: glyphCount)
        }
        throw FontError.unsupportedCmap
    }

    static func readFormat4(reader: BinaryReader, offset: Int, glyphCount: Int) throws -> [UInt32: UInt16] {
        guard try reader.uint16(at: offset) == 4 else { throw FontError.invalidTable("cmap") }
        let length = Int(try reader.uint16(at: offset + 2))
        let segmentCount = Int(try reader.uint16(at: offset + 6)) / 2
        guard length >= 16 + segmentCount * 8 else { throw FontError.invalidTable("cmap") }
        try reader.require(offset: offset, length: length)

        let endCodes = offset + 14
        let startCodes = endCodes + segmentCount * 2 + 2
        let deltas = startCodes + segmentCount * 2
        let rangeOffsets = deltas + segmentCount * 2
        var result: [UInt32: UInt16] = [:]

        for segment in 0..<segmentCount {
            let start = UInt32(try reader.uint16(at: startCodes + segment * 2))
            let end = UInt32(try reader.uint16(at: endCodes + segment * 2))
            guard start <= end, start <= 0xFFFF else { continue }
            let boundedEnd = min(end, 0xFFFF)
            let delta = Int32(try reader.int16(at: deltas + segment * 2))
            let rangeOffset = Int(try reader.uint16(at: rangeOffsets + segment * 2))
            var codePoint = start
            while codePoint <= boundedEnd {
                let glyphIndex: UInt16
                if rangeOffset == 0 {
                    glyphIndex = UInt16(truncatingIfNeeded: Int64(codePoint) + Int64(delta))
                } else {
                    let glyphAddress = rangeOffsets + segment * 2 + rangeOffset + Int((codePoint - start) * 2)
                    let raw = try reader.uint16(at: glyphAddress)
                    glyphIndex = raw == 0 ? 0 : UInt16(truncatingIfNeeded: Int32(raw) + delta)
                }
                if glyphIndex != 0, Int(glyphIndex) < glyphCount, codePoint != 0xFFFF,
                   !(0xD800...0xDFFF).contains(codePoint) {
                    result[codePoint] = glyphIndex
                }
                if codePoint == boundedEnd { break }
                codePoint += 1
            }
        }
        return result
    }

    static func readFormat12(reader: BinaryReader, offset: Int, glyphCount: Int) throws -> [UInt32: UInt16] {
        guard try reader.uint16(at: offset) == 12 else { throw FontError.invalidTable("cmap") }
        let length = Int(try reader.uint32(at: offset + 4))
        let groupCount = Int(try reader.uint32(at: offset + 12))
        guard length >= 16 + groupCount * 12 else { throw FontError.invalidTable("cmap") }
        try reader.require(offset: offset, length: length)
        guard groupCount <= 2_000_000 else { throw FontError.invalidValue("The cmap has too many groups.") }

        var result: [UInt32: UInt16] = [:]
        for group in 0..<groupCount {
            let record = offset + 16 + group * 12
            let start = try reader.uint32(at: record)
            let end = try reader.uint32(at: record + 4)
            let firstGlyph = try reader.uint32(at: record + 8)
            guard start <= end else { throw FontError.invalidTable("cmap") }
            let span = UInt64(end) - UInt64(start) + 1
            guard span <= 2_000_000 else { throw FontError.invalidValue("A cmap range is too large.") }
            for value in 0..<span {
                let codePoint = UInt64(start) + value
                let glyphIndex = UInt64(firstGlyph) + value
                if codePoint <= 0x10FFFF, glyphIndex > 0, glyphIndex < UInt64(glyphCount),
                   !(0xD800...0xDFFF).contains(UInt32(codePoint)) {
                    result[UInt32(codePoint)] = UInt16(glyphIndex)
                }
            }
        }
        return result
    }

    static func readFamilyName(reader: BinaryReader, table: TableRecord?) -> String? {
        guard let table, table.length >= 6,
              let count = try? reader.uint16(at: table.offset + 2),
              let stringOffset = try? reader.uint16(at: table.offset + 4) else { return nil }

        var preferred: (score: Int, value: String)?
        for index in 0..<Int(count) {
            let record = table.offset + 6 + index * 12
            guard record + 12 <= table.offset + table.length,
                  let platform = try? reader.uint16(at: record),
                  let encoding = try? reader.uint16(at: record + 2),
                  let language = try? reader.uint16(at: record + 4),
                  let nameID = try? reader.uint16(at: record + 6),
                  let length = try? reader.uint16(at: record + 8),
                  let recordStringOffset = try? reader.uint16(at: record + 10),
                  nameID == 1 else { continue }

            let valueOffset = table.offset + Int(stringOffset) + Int(recordStringOffset)
            guard valueOffset >= table.offset,
                  valueOffset + Int(length) <= table.offset + table.length,
                  let valueData = try? reader.subdata(offset: valueOffset, length: Int(length)) else { continue }

            let value: String
            if platform == 3 || platform == 0 {
                var units: [UInt16] = []
                var cursor = 0
                while cursor + 1 < valueData.count {
                    units.append((UInt16(valueData[cursor]) << 8) | UInt16(valueData[cursor + 1]))
                    cursor += 2
                }
                value = String(decoding: units, as: UTF16.self)
            } else {
                value = String(decoding: valueData, as: UTF8.self)
            }
            let score = (platform == 3 ? 4 : 0) + (encoding == 1 ? 2 : 0) + (language == 0x0409 ? 1 : 0)
            if !value.isEmpty, preferred == nil || score > preferred!.score {
                preferred = (score, value)
            }
        }
        return preferred?.value
    }
}
