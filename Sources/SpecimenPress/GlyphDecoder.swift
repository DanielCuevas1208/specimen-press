import Foundation

final class GlyphDecoder {
    private let reader: BinaryReader
    private let glyf: TableRecord
    private let offsets: [Int]
    private let glyphCount: Int
    private var cache: [Int: GlyphOutline] = [:]
    private var active: Set<Int> = []

    init(reader: BinaryReader, glyf: TableRecord, offsets: [Int], glyphCount: Int) {
        self.reader = reader
        self.glyf = glyf
        self.offsets = offsets
        self.glyphCount = glyphCount
    }

    func outline(for index: Int) throws -> GlyphOutline? {
        guard index >= 0, index < glyphCount else { throw FontError.invalidValue("Glyph index is out of range.") }
        if let cached = cache[index] { return cached }
        let start = offsets[index]
        let end = offsets[index + 1]
        guard end >= start, end <= glyf.length else { throw FontError.invalidTable("glyf") }
        guard end - start >= 10 else {
            let empty = GlyphOutline(bounds: GlyphBounds(minX: 0, minY: 0, maxX: 0, maxY: 0), contours: [])
            cache[index] = empty
            return empty
        }
        guard active.insert(index).inserted else {
            throw FontError.unsupportedGlyph("Composite glyph recursion is circular.")
        }
        defer { active.remove(index) }

        let base = glyf.offset + start
        let contourCount = try reader.int16(at: base)
        let bounds = GlyphBounds(
            minX: Double(try reader.int16(at: base + 2)),
            minY: Double(try reader.int16(at: base + 4)),
            maxX: Double(try reader.int16(at: base + 6)),
            maxY: Double(try reader.int16(at: base + 8))
        )

        let result: GlyphOutline
        if contourCount >= 0 {
            result = try readSimple(base: base, end: glyf.offset + end, contourCount: Int(contourCount), bounds: bounds)
        } else {
            result = try readComposite(base: base, end: glyf.offset + end, bounds: bounds)
        }
        cache[index] = result
        return result
    }

    private func readSimple(base: Int, end: Int, contourCount: Int, bounds: GlyphBounds) throws -> GlyphOutline {
        guard contourCount <= 32_768 else { throw FontError.invalidValue("The glyph has too many contours.") }
        let endPointsStart = base + 10
        let instructionLengthOffset = endPointsStart + contourCount * 2
        guard instructionLengthOffset + 2 <= end else { throw FontError.invalidTable("glyf") }

        var endPoints: [Int] = []
        for index in 0..<contourCount {
            endPoints.append(Int(try reader.uint16(at: endPointsStart + index * 2)))
        }
        let pointCount = (endPoints.last ?? -1) + 1
        guard pointCount >= 0, pointCount <= 2_000_000 else {
            throw FontError.invalidValue("The glyph has too many points.")
        }
        let instructionLength = Int(try reader.uint16(at: instructionLengthOffset))
        var cursor = instructionLengthOffset + 2 + instructionLength
        guard cursor <= end else { throw FontError.invalidTable("glyf") }

        var flags: [UInt8] = []
        flags.reserveCapacity(pointCount)
        while flags.count < pointCount {
            let flag = try reader.uint8(at: cursor)
            cursor += 1
            flags.append(flag)
            if flag & 0x08 != 0 {
                let repeatCount = Int(try reader.uint8(at: cursor))
                cursor += 1
                guard flags.count + repeatCount <= pointCount else { throw FontError.invalidTable("glyf") }
                flags.append(contentsOf: repeatElement(flag, count: repeatCount))
            }
        }

        var xValues: [Double] = []
        var yValues: [Double] = []
        xValues.reserveCapacity(pointCount)
        yValues.reserveCapacity(pointCount)
        var x = 0
        for flag in flags {
            if flag & 0x02 != 0 {
                let delta = Int(try reader.uint8(at: cursor))
                cursor += 1
                x += flag & 0x10 != 0 ? delta : -delta
            } else if flag & 0x10 == 0 {
                x += Int(try reader.int16(at: cursor))
                cursor += 2
            }
            xValues.append(Double(x))
        }

        var y = 0
        for flag in flags {
            if flag & 0x04 != 0 {
                let delta = Int(try reader.uint8(at: cursor))
                cursor += 1
                y += flag & 0x20 != 0 ? delta : -delta
            } else if flag & 0x20 == 0 {
                y += Int(try reader.int16(at: cursor))
                cursor += 2
            }
            yValues.append(Double(y))
        }

        var contours: [GlyphContour] = []
        var pointStart = 0
        for endPoint in endPoints {
            guard endPoint >= pointStart, endPoint < pointCount else { throw FontError.invalidTable("glyf") }
            let points = (pointStart...endPoint).map { pointIndex in
                GlyphPoint(
                    x: xValues[pointIndex],
                    y: yValues[pointIndex],
                    isOnCurve: flags[pointIndex] & 0x01 != 0
                )
            }
            contours.append(GlyphContour(points: points))
            pointStart = endPoint + 1
        }
        return GlyphOutline(bounds: bounds, contours: contours)
    }

    private func readComposite(base: Int, end: Int, bounds: GlyphBounds) throws -> GlyphOutline {
        var cursor = base + 10
        var contours: [GlyphContour] = []
        var parentPoints: [GlyphPoint] = []
        var hasMore = true
        var componentCount = 0

        while hasMore {
            componentCount += 1
            guard componentCount <= 256, cursor + 4 <= end else {
                throw FontError.invalidValue("The composite glyph has too many components.")
            }
            let flags = try reader.uint16(at: cursor)
            let componentIndex = Int(try reader.uint16(at: cursor + 2))
            cursor += 4
            guard componentIndex < glyphCount else { throw FontError.invalidValue("Composite glyph index is invalid.") }

            let arg1: Int
            let arg2: Int
            if flags & 0x0001 != 0 {
                arg1 = Int(try reader.int16(at: cursor))
                arg2 = Int(try reader.int16(at: cursor + 2))
                cursor += 4
            } else {
                arg1 = Int(try reader.int8(at: cursor))
                arg2 = Int(try reader.int8(at: cursor + 1))
                cursor += 2
            }

            let matrix = try readMatrix(flags: flags, cursor: &cursor, end: end)
            guard let component = try outline(for: componentIndex) else {
                throw FontError.unsupportedGlyph("A composite component has no outline.")
            }
            var transformedContours = component.contours.map { contour in
                GlyphContour(points: contour.points.map { point in
                    GlyphPoint(
                        x: matrix.a * point.x + matrix.c * point.y,
                        y: matrix.b * point.x + matrix.d * point.y,
                        isOnCurve: point.isOnCurve
                    )
                })
            }

            let translation: (Double, Double)
            if flags & 0x0002 != 0 {
                translation = (Double(arg1), Double(arg2))
            } else {
                let componentPoints = component.contours.flatMap(\.points)
                guard arg1 >= 0, arg1 < parentPoints.count,
                      arg2 >= 0, arg2 < componentPoints.count else {
                    throw FontError.unsupportedGlyph("Point-matched composite arguments are out of range.")
                }
                let componentPoint = componentPoints[arg2]
                let transformedPoint = GlyphPoint(
                    x: matrix.a * componentPoint.x + matrix.c * componentPoint.y,
                    y: matrix.b * componentPoint.x + matrix.d * componentPoint.y,
                    isOnCurve: componentPoint.isOnCurve
                )
                translation = (parentPoints[arg1].x - transformedPoint.x, parentPoints[arg1].y - transformedPoint.y)
            }

            transformedContours = transformedContours.map { contour in
                GlyphContour(points: contour.points.map { point in
                    GlyphPoint(x: point.x + translation.0, y: point.y + translation.1, isOnCurve: point.isOnCurve)
                })
            }
            contours.append(contentsOf: transformedContours)
            parentPoints = contours.flatMap(\.points)
            hasMore = flags & 0x0020 != 0
            if !hasMore, flags & 0x0100 != 0 {
                guard cursor + 2 <= end else { throw FontError.invalidTable("glyf") }
                let instructionLength = Int(try reader.uint16(at: cursor))
                cursor += 2 + instructionLength
                guard cursor <= end else { throw FontError.invalidTable("glyf") }
            }
        }
        return GlyphOutline(bounds: bounds, contours: contours)
    }

    private struct Matrix {
        let a: Double
        let b: Double
        let c: Double
        let d: Double
    }

    private func readMatrix(flags: UInt16, cursor: inout Int, end: Int) throws -> Matrix {
        if flags & 0x0080 != 0 {
            guard cursor + 8 <= end else { throw FontError.invalidTable("glyf") }
            let a = try fixed2Dot14(at: cursor)
            let b = try fixed2Dot14(at: cursor + 2)
            let c = try fixed2Dot14(at: cursor + 4)
            let d = try fixed2Dot14(at: cursor + 6)
            cursor += 8
            return Matrix(a: a, b: b, c: c, d: d)
        }
        if flags & 0x0040 != 0 {
            guard cursor + 4 <= end else { throw FontError.invalidTable("glyf") }
            let x = try fixed2Dot14(at: cursor)
            let y = try fixed2Dot14(at: cursor + 2)
            cursor += 4
            return Matrix(a: x, b: 0, c: 0, d: y)
        }
        if flags & 0x0008 != 0 {
            guard cursor + 2 <= end else { throw FontError.invalidTable("glyf") }
            let scale = try fixed2Dot14(at: cursor)
            cursor += 2
            return Matrix(a: scale, b: 0, c: 0, d: scale)
        }
        return Matrix(a: 1, b: 0, c: 0, d: 1)
    }

    private func fixed2Dot14(at offset: Int) throws -> Double {
        Double(try reader.int16(at: offset)) / 16_384.0
    }
}
