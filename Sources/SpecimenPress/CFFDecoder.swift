import Foundation

final class CFFDecoder {
    private let reader: BinaryReader
    private let table: TableRecord
    private let isCFF2: Bool
    private let glyphCount: Int
    private let charStrings: [Data]
    private let globalSubrs: [Data]
    private let localSubrs: [Data]
    private var cache: [Int: GlyphOutline] = [:]

    init(reader: BinaryReader, table: TableRecord, isCFF2: Bool, glyphCount: Int) throws {
        self.reader = reader
        self.table = table
        self.isCFF2 = isCFF2
        self.glyphCount = glyphCount

        let base = table.offset
        guard table.length >= 4 else { throw FontError.invalidTable(isCFF2 ? "CFF2" : "CFF ") }

        let major = try reader.uint8(at: base)
        guard major == (isCFF2 ? 2 : 1) else {
            throw FontError.invalidValue("The CFF header version is unsupported.")
        }

        let topDictData: Data
        if isCFF2 {
            guard table.length >= 5 else { throw FontError.invalidTable("CFF2") }
            let hdrSize = Int(try reader.uint8(at: base + 2))
            let topDictLength = Int(try reader.uint16(at: base + 3))
            guard hdrSize >= 5, topDictLength > 0 else { throw FontError.invalidTable("CFF2") }
            try reader.require(offset: base + hdrSize, length: topDictLength)
            topDictData = try reader.subdata(offset: base + hdrSize, length: topDictLength)
            var cursor = base + hdrSize + topDictLength
            cursor = try Self.skipIndex(reader: reader, offset: cursor)
            globalSubrs = try Self.readIndex(reader: reader, offset: cursor)
        } else {
            var cursor = base + Int(try reader.uint8(at: base + 2))
            cursor = try Self.skipIndex(reader: reader, offset: cursor)
            topDictData = try Self.readIndexItem(reader: reader, offset: cursor, index: 0)
            cursor = try Self.skipIndex(reader: reader, offset: cursor)
            cursor = try Self.skipIndex(reader: reader, offset: cursor)
            globalSubrs = try Self.readIndex(reader: reader, offset: cursor)
        }

        let topDict = try Self.parseDict(data: topDictData, isCFF2: isCFF2)
        let charStringsKey = isCFF2 ? 17 : 14
        guard let charStringsOffset = topDict.offsets[charStringsKey] else {
            throw FontError.invalidTable(isCFF2 ? "CFF2" : "CFF ")
        }
        let privateInfo = topDict.privateInfo

        charStrings = try Self.readIndex(reader: reader, offset: base + charStringsOffset)

        if let privateInfo {
            let privateData = try reader.subdata(
                offset: base + privateInfo.offset,
                length: privateInfo.size
            )
            let privateDict = try Self.parseDict(data: privateData, isCFF2: isCFF2)
            if let localOffset = privateDict.offsets[19] {
                localSubrs = try Self.readIndex(
                    reader: reader,
                    offset: base + privateInfo.offset + localOffset
                )
            } else {
                localSubrs = []
            }
        } else {
            localSubrs = []
        }
    }

    func outline(for index: Int) throws -> GlyphOutline? {
        guard index >= 0, index < glyphCount else {
            throw FontError.invalidValue("Glyph index is out of range.")
        }
        if let cached = cache[index] { return cached }

        guard index < charStrings.count else {
            let empty = GlyphOutline(bounds: GlyphBounds(minX: 0, minY: 0, maxX: 0, maxY: 0), contours: [])
            cache[index] = empty
            return empty
        }

        let interpreter = CharStringInterpreter(
            isCFF2: isCFF2,
            globalSubrs: globalSubrs,
            localSubrs: localSubrs
        )
        let result = try interpreter.outline(from: charStrings[index])
        cache[index] = result
        return result
    }
}

private extension CFFDecoder {
    struct DictValues {
        var offsets: [Int: Int] = [:]
        var privateInfo: (size: Int, offset: Int)?
    }

    static func skipIndex(reader: BinaryReader, offset: Int) throws -> Int {
        let count = try readIndexCount(reader: reader, offset: offset)
        guard count >= 0 else { throw FontError.invalidTable("CFF") }
        if count == 0 { return offset + indexCountSize(reader: reader, offset: offset) }

        let countFieldSize = indexCountSize(reader: reader, offset: offset)
        let offSize = Int(try reader.uint8(at: offset + countFieldSize))
        guard offSize >= 1, offSize <= 4 else { throw FontError.invalidTable("CFF") }
        return offset + countFieldSize + 1 + (count + 1) * offSize
    }

    static func readIndex(reader: BinaryReader, offset: Int) throws -> [Data] {
        let count = try readIndexCount(reader: reader, offset: offset)
        guard count >= 0 else { throw FontError.invalidTable("CFF") }
        if count == 0 { return [] }

        let countFieldSize = indexCountSize(reader: reader, offset: offset)
        let offSize = Int(try reader.uint8(at: offset + countFieldSize))
        guard offSize >= 1, offSize <= 4 else { throw FontError.invalidTable("CFF") }

        let offsetsStart = offset + countFieldSize + 1
        let dataStart = offsetsStart + (count + 1) * offSize
        var items: [Data] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            let start = try readIndexOffset(reader: reader, at: offsetsStart + index * offSize, size: offSize) - 1
            let end = try readIndexOffset(reader: reader, at: offsetsStart + (index + 1) * offSize, size: offSize) - 1
            guard end >= start else { throw FontError.invalidTable("CFF") }
            items.append(try reader.subdata(offset: dataStart + start, length: end - start))
        }
        return items
    }

    static func readIndexItem(reader: BinaryReader, offset: Int, index: Int) throws -> Data {
        let items = try readIndex(reader: reader, offset: offset)
        guard index < items.count else { throw FontError.invalidTable("CFF") }
        return items[index]
    }

    static func readIndexCount(reader: BinaryReader, offset: Int) throws -> Int {
        let first = try reader.uint16(at: offset)
        if first != 0xFFFF { return Int(first) }
        return Int(try reader.uint32(at: offset + 2))
    }

    static func indexCountSize(reader: BinaryReader, offset: Int) throws -> Int {
        let first = try reader.uint16(at: offset)
        return first == 0xFFFF ? 6 : 2
    }

    static func readIndexOffset(reader: BinaryReader, at offset: Int, size: Int) throws -> Int {
        switch size {
        case 1: return Int(try reader.uint8(at: offset))
        case 2: return Int(try reader.uint16(at: offset))
        case 3:
            let bytes = try reader.subdata(offset: offset, length: 3)
            return (Int(bytes[0]) << 16) | (Int(bytes[1]) << 8) | Int(bytes[2])
        case 4: return Int(try reader.uint32(at: offset))
        default: throw FontError.invalidTable("CFF")
        }
    }

    static func parseDict(data: Data, isCFF2: Bool) throws -> DictValues {
        var values = DictValues()
        var operands: [Int] = []
        var cursor = 0

        while cursor < data.count {
            let byte = data[cursor]
            cursor += 1

            if byte >= 32 {
                operands.append(try decodeCFFOperand(byte, data: data, cursor: &cursor))
                continue
            }

            let operatorCode: Int
            if byte == 12 {
                guard cursor < data.count else { throw FontError.invalidTable("CFF") }
                operatorCode = 1000 + Int(data[cursor])
                cursor += 1
            } else {
                operatorCode = Int(byte)
            }

            switch operatorCode {
            case 14, 17:
                guard let offset = operands.last else { throw FontError.invalidTable("CFF") }
                values.offsets[operatorCode] = offset
            case 18:
                guard operands.count >= 2 else { throw FontError.invalidTable("CFF") }
                values.privateInfo = (operands[operands.count - 2], operands[operands.count - 1])
            case 19:
                guard let offset = operands.last else { throw FontError.invalidTable("CFF") }
                values.offsets[19] = offset
            default:
                break
            }
            operands.removeAll(keepingCapacity: true)
        }
        return values
    }

    static func decodeOperand(_ firstByte: UInt8, data: Data, cursor: inout Int) throws -> Int {
        try decodeCFFOperand(firstByte, data: data, cursor: &cursor)
    }
}

private func decodeCFFOperand(_ firstByte: UInt8, data: Data, cursor: inout Int) throws -> Int {
    let byte = Int(firstByte)
    if byte >= 32, byte <= 246 { return byte - 139 }
    if byte >= 247, byte <= 250 {
        guard cursor < data.count else { throw FontError.invalidTable("CFF") }
        return (byte - 247) * 256 + Int(data[cursor]) + 108
    }
    if byte >= 251, byte <= 254 {
        guard cursor < data.count else { throw FontError.invalidTable("CFF") }
        return -(byte - 251) * 256 - Int(data[cursor]) - 108
    }
    if byte == 28 {
        guard cursor + 1 < data.count else { throw FontError.invalidTable("CFF") }
        let value = (Int(data[cursor]) << 8) | Int(data[cursor + 1])
        cursor += 2
        return value >= 0x8000 ? value - 0x10000 : value
    }
    if byte == 29 {
        guard cursor + 3 < data.count else { throw FontError.invalidTable("CFF") }
        let value = (Int(data[cursor]) << 24)
            | (Int(data[cursor + 1]) << 16)
            | (Int(data[cursor + 2]) << 8)
            | Int(data[cursor + 3])
        cursor += 4
        return value
    }
    throw FontError.invalidTable("CFF")
}

private final class CharStringInterpreter {
    private let isCFF2: Bool
    private let globalSubrs: [Data]
    private let localSubrs: [Data]
    private var callDepth = 0

    init(isCFF2: Bool, globalSubrs: [Data], localSubrs: [Data]) {
        self.isCFF2 = isCFF2
        self.globalSubrs = globalSubrs
        self.localSubrs = localSubrs
    }

    func outline(from data: Data) throws -> GlyphOutline {
        var builder = OutlineBuilder()
        try execute(data, builder: &builder)
        return builder.finish()
    }

    private func execute(_ data: Data, builder: inout OutlineBuilder) throws {
        guard callDepth < 16 else { throw FontError.unsupportedGlyph("CharString recursion is too deep.") }
        callDepth += 1
        defer { callDepth -= 1 }

        var stack: [Double] = []
        var cursor = 0
        while cursor < data.count {
            let byte = data[cursor]
            cursor += 1

            if byte >= 32 {
                stack.append(Double(try decodeCFFOperand(byte, data: data, cursor: &cursor)))
                continue
            }

            if byte == 12 {
                guard cursor < data.count else { throw FontError.invalidTable("CFF") }
                let escaped = data[cursor]
                cursor += 1
                switch escaped {
                case 34: try builder.hhcurveto(stack: &stack)
                case 35: try builder.vhcurveto(stack: &stack)
                case 36: try builder.hvcurveto(stack: &stack)
                case 37: try builder.vvcurveto(stack: &stack)
                default: stack.removeAll(keepingCapacity: true)
                }
                continue
            }

            switch byte {
            case 1, 3: stack.removeAll(keepingCapacity: true)
            case 4: try builder.vmoveto(stack: &stack)
            case 5: try builder.rlineto(stack: &stack)
            case 6: try builder.hlineto(stack: &stack)
            case 7: try builder.vlineto(stack: &stack)
            case 8: try builder.rrcurveto(stack: &stack)
            case 10:
                let index = try subrIndex(from: &stack, count: localSubrs.count)
                try execute(localSubrs[index], builder: &builder)
            case 11: return
            case 14:
                builder.closeContour()
                return
            case 21: try builder.rmoveto(stack: &stack)
            case 22: try builder.hmoveto(stack: &stack)
            case 29:
                let index = try subrIndex(from: &stack, count: globalSubrs.count)
                try execute(globalSubrs[index], builder: &builder)
            default:
                stack.removeAll(keepingCapacity: true)
            }
        }
    }

    private func subrIndex(from stack: inout [Double], count: Int) throws -> Int {
        guard let raw = stack.popLast() else { throw FontError.invalidTable("CFF") }
        let index = Int(raw) + bias(for: count)
        guard index >= 0, index < count else { throw FontError.unsupportedGlyph("CharString subroutine index is out of range.") }
        return index
    }

    private func bias(for count: Int) -> Int {
        if isCFF2 {
            if count < 1240 { return 107 }
            if count < 33_900 { return 1_131 }
            return 32_768
        }
        if count < 1240 { return 107 }
        if count < 3_390 { return 1_131 }
        return 32_768
    }
}

private struct OutlineBuilder {
    private var contours: [GlyphContour] = []
    private var currentPoints: [GlyphPoint] = []
    private var x = 0.0
    private var y = 0.0
    private var minX = 0.0
    private var minY = 0.0
    private var maxX = 0.0
    private var maxY = 0.0
    private var hasPoint = false

    mutating func rmoveto(stack: inout [Double]) throws {
        let dx: Double
        let dy: Double
        if stack.count >= 2 {
            dx = stack.removeFirst()
            dy = stack.removeFirst()
        } else if let value = stack.popLast() {
            dx = value
            dy = 0
        } else {
            throw FontError.invalidTable("CFF")
        }
        startContour()
        move(dx: dx, dy: dy)
        stack.removeAll(keepingCapacity: true)
    }

    mutating func hmoveto(stack: inout [Double]) throws {
        guard let dx = stack.popLast() else { throw FontError.invalidTable("CFF") }
        startContour()
        move(dx: dx, dy: 0)
        stack.removeAll(keepingCapacity: true)
    }

    mutating func vmoveto(stack: inout [Double]) throws {
        guard let dy = stack.popLast() else { throw FontError.invalidTable("CFF") }
        startContour()
        move(dx: 0, dy: dy)
        stack.removeAll(keepingCapacity: true)
    }

    mutating func rlineto(stack: inout [Double]) throws {
        while stack.count >= 2 {
            let dx = stack.removeFirst()
            let dy = stack.removeFirst()
            line(dx: dx, dy: dy)
        }
    }

    mutating func hlineto(stack: inout [Double]) throws {
        while let dx = stack.first {
            stack.removeFirst()
            line(dx: dx, dy: 0)
            guard let dy = stack.first else { break }
            stack.removeFirst()
            line(dx: 0, dy: dy)
        }
    }

    mutating func vlineto(stack: inout [Double]) throws {
        while let dy = stack.first {
            stack.removeFirst()
            line(dx: 0, dy: dy)
            guard let dx = stack.first else { break }
            stack.removeFirst()
            line(dx: dx, dy: 0)
        }
    }

    mutating func rrcurveto(stack: inout [Double]) throws {
        while stack.count >= 6 {
            let dx1 = stack.removeFirst()
            let dy1 = stack.removeFirst()
            let dx2 = stack.removeFirst()
            let dy2 = stack.removeFirst()
            let dx = stack.removeFirst()
            let dy = stack.removeFirst()
            curve(dx1: dx1, dy1: dy1, dx2: dx2, dy2: dy2, dx: dx, dy: dy)
        }
    }

    mutating func hhcurveto(stack: inout [Double]) throws {
        var index = 0
        while index + 3 < stack.count {
            let dy1 = index == 0 && stack.count.isMultiple(of: 2) ? stack.removeFirst() : 0
            let dx1 = stack.removeFirst()
            let dx2 = stack.removeFirst()
            let dy2 = stack.removeFirst()
            let dx = stack.removeFirst()
            curve(dx1: dx1, dy1: dy1, dx2: dx2, dy2: dy2, dx: dx, dy: 0)
            index += 4
        }
        stack.removeAll(keepingCapacity: true)
    }

    mutating func vvcurveto(stack: inout [Double]) throws {
        while stack.count >= 4 {
            let dx1 = stack.count.isMultiple(of: 2) ? stack.removeFirst() : 0
            let dy1 = stack.removeFirst()
            let dy2 = stack.removeFirst()
            let dx2 = stack.removeFirst()
            let dy = stack.removeFirst()
            curve(dx1: dx1, dy1: dy1, dx2: dx2, dy2: dy2, dx: 0, dy: dy)
        }
        stack.removeAll(keepingCapacity: true)
    }

    mutating func hvcurveto(stack: inout [Double]) throws {
        try alternatingCurveto(stack: &stack, horizontalFirst: true)
    }

    mutating func vhcurveto(stack: inout [Double]) throws {
        try alternatingCurveto(stack: &stack, horizontalFirst: false)
    }

    mutating func closeContour() {
        guard !currentPoints.isEmpty else { return }
        contours.append(GlyphContour(points: currentPoints))
        currentPoints = []
    }

    mutating func finish() -> GlyphOutline {
        closeContour()
        let bounds = hasPoint
            ? GlyphBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            : GlyphBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
        return GlyphOutline(bounds: bounds, contours: contours)
    }

    private mutating func startContour() {
        closeContour()
    }

    private mutating func move(dx: Double, dy: Double) {
        x += dx
        y += dy
        addPoint(x: x, y: y, onCurve: true)
    }

    private mutating func line(dx: Double, dy: Double) {
        x += dx
        y += dy
        addPoint(x: x, y: y, onCurve: true)
    }

    private mutating func curve(dx1: Double, dy1: Double, dx2: Double, dy2: Double, dx: Double, dy: Double) {
        addPoint(x: x + dx1, y: y + dy1, onCurve: false)
        addPoint(x: x + dx2, y: y + dy2, onCurve: false)
        x += dx
        y += dy
        addPoint(x: x, y: y, onCurve: true)
    }

    private mutating func addPoint(x: Double, y: Double, onCurve: Bool) {
        currentPoints.append(GlyphPoint(x: x, y: y, isOnCurve: onCurve))
        if hasPoint {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        } else {
            minX = x
            minY = y
            maxX = x
            maxY = y
            hasPoint = true
        }
    }

    private mutating func alternatingCurveto(stack: inout [Double], horizontalFirst: Bool) throws {
        var horizontal = horizontalFirst
        while stack.count >= 4 {
            if horizontal {
                let dy1 = stack.count.isMultiple(of: 2) ? stack.removeFirst() : 0
                let dx1 = stack.removeFirst()
                let dx2 = stack.removeFirst()
                let dy2 = stack.removeFirst()
                let dx = stack.removeFirst()
                curve(dx1: dx1, dy1: dy1, dx2: dx2, dy2: dy2, dx: dx, dy: 0)
            } else {
                let dx1 = stack.count.isMultiple(of: 2) ? stack.removeFirst() : 0
                let dy1 = stack.removeFirst()
                let dy2 = stack.removeFirst()
                let dx2 = stack.removeFirst()
                let dy = stack.removeFirst()
                curve(dx1: dx1, dy1: dy1, dx2: dx2, dy2: dy2, dx: 0, dy: dy)
            }
            horizontal.toggle()
        }
        stack.removeAll(keepingCapacity: true)
    }
}
