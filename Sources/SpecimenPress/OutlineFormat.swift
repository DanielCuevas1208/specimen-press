import Foundation

public enum OutlineFormat: String, Codable, Equatable {
    case trueType
    case cff
    case cff2

    public var label: String {
        switch self {
        case .trueType: return "TRUE TYPE"
        case .cff: return "CFF"
        case .cff2: return "CFF2"
        }
    }
}
