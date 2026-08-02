import Foundation

public struct GlyphPoint: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let isOnCurve: Bool

    public init(x: Double, y: Double, isOnCurve: Bool) {
        self.x = x
        self.y = y
        self.isOnCurve = isOnCurve
    }
}

public struct GlyphContour: Codable, Equatable {
    public let points: [GlyphPoint]

    public init(points: [GlyphPoint]) {
        self.points = points
    }
}

public struct GlyphBounds: Codable, Equatable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { max(0, maxX - minX) }
    public var height: Double { max(0, maxY - minY) }
}

public struct GlyphOutline: Codable, Equatable {
    public let bounds: GlyphBounds
    public let contours: [GlyphContour]

    public init(bounds: GlyphBounds, contours: [GlyphContour]) {
        self.bounds = bounds
        self.contours = contours
    }

    public var isEmpty: Bool { contours.isEmpty }

    public func svgPath() -> String {
        contours.map { Self.svgPath(for: $0) }.joined(separator: " ")
    }

    private static func svgPath(for contour: GlyphContour) -> String {
        let points = contour.points
        guard !points.isEmpty else { return "" }

        let first = points[0]
        let last = points[points.count - 1]
        let start: GlyphPoint
        let remaining: [GlyphPoint]

        if first.isOnCurve {
            start = first
            remaining = Array(points.dropFirst())
        } else if last.isOnCurve {
            start = last
            remaining = Array(points.dropLast())
        } else {
            start = midpoint(last, first)
            remaining = points
        }

        guard !remaining.isEmpty else {
            return "M \(number(start.x)) \(number(start.y)) Z"
        }

        var result = "M \(number(start.x)) \(number(start.y))"
        var current = start
        var index = 0

        while index < remaining.count {
            let point = remaining[index]
            if point.isOnCurve {
                result += " L \(number(point.x)) \(number(point.y))"
                current = point
                index += 1
                continue
            }

            let nextIndex = index + 1
            let next = nextIndex < remaining.count ? remaining[nextIndex] : start
            if next.isOnCurve {
                result += " Q \(number(point.x)) \(number(point.y)) \(number(next.x)) \(number(next.y))"
                current = next
                index += 2
            } else {
                let implied = midpoint(point, next)
                result += " Q \(number(point.x)) \(number(point.y)) \(number(implied.x)) \(number(implied.y))"
                current = implied
                index += 1
            }
        }

        if current != start {
            result += " L \(number(start.x)) \(number(start.y))"
        }
        return result + " Z"
    }

    private static func midpoint(_ first: GlyphPoint, _ second: GlyphPoint) -> GlyphPoint {
        GlyphPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2, isOnCurve: true)
    }

    private static func number(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

public struct GlyphMetrics: Codable, Equatable {
    public let advanceWidth: UInt16
    public let leftSideBearing: Int16

    public init(advanceWidth: UInt16, leftSideBearing: Int16) {
        self.advanceWidth = advanceWidth
        self.leftSideBearing = leftSideBearing
    }
}

public struct Glyph: Codable, Equatable {
    public let index: UInt16
    public let metrics: GlyphMetrics
    public let outline: GlyphOutline?

    public init(index: UInt16, metrics: GlyphMetrics, outline: GlyphOutline?) {
        self.index = index
        self.metrics = metrics
        self.outline = outline
    }

    public var hasOutline: Bool { outline?.isEmpty == false }
