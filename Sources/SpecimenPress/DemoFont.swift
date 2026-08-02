import Foundation

public enum DemoFont {
    public static func data() throws -> Data {
        guard let url = Bundle.module.url(forResource: "SpecimenPressFixture", withExtension: "ttf") else {
            throw FontError.invalidValue("The bundled demo font is missing.")
        }
        return try Data(contentsOf: url)
    }

    public static func load() throws -> TrueTypeFont {
        try TrueTypeFont(data: data())
    }
}
