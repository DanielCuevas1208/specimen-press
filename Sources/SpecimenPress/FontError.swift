import Foundation

public enum FontError: Error, LocalizedError, Equatable {
    case dataTooShort(offset: Int, length: Int)
    case invalidSignature
    case invalidTable(String)
    case missingTable(String)
    case unsupportedCmap
    case unsupportedGlyph(String)
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case let .dataTooShort(offset, length):
            return "Font data ends before offset \(offset) can provide \(length) bytes."
        case .invalidSignature:
            return "The file is not a supported TrueType or OpenType font."
        case let .invalidTable(tag):
            return "The \(tag) table is malformed."
        case let .missingTable(tag):
            return "The font does not contain the required \(tag) table."
        case .unsupportedCmap:
            return "The font has no supported Unicode character map."
        case let .unsupportedGlyph(reason):
            return "The glyph outline cannot be decoded: \(reason)"
        case let .invalidValue(reason):
            return "The font contains an invalid value: \(reason)"
