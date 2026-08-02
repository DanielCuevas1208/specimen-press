import Foundation

public enum DemoFont {
    public static func data() throws -> Data {
        try loadResource(named: "SpecimenPressFixture", extension: "ttf")
    }

    public static func cffData() throws -> Data {
        try loadResource(named: "SpecimenPressCFF", extension: "otf")
    }

    public static func cff2Data() throws -> Data {
        try loadResource(named: "SpecimenPressCFF2", extension: "otf")
    }

    public static func load() throws -> TrueTypeFont {
        try TrueTypeFont(data: data())
    }

    public static func loadCFF() throws -> TrueTypeFont {
        try TrueTypeFont(data: cffData())
    }

    public static func loadCFF2() throws -> TrueTypeFont {
        try TrueTypeFont(data: cff2Data())
    }

    private static func loadResource(named name: String, extension ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw FontError.invalidValue("The bundled demo font \(name).\(ext) is missing.")
        }
        return try Data(contentsOf: url)
    }
}
