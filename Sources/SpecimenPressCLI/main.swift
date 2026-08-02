import Foundation
import SpecimenPress

@main
struct SpecimenPressCLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data(("Error: \(error.localizedDescription)\n").utf8))
        }
    }

    private static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            print(usage)
            return
        }

        switch command {
        case "demo":
            let output = optionValue("--output", in: arguments) ?? "SpecimenPress.svg"
            try write(
                renderer: SpecimenRenderer(),
                font: try DemoFont.load(),
                output: output,
                sampleText: optionValue("--sample", in: arguments)
            )
        case "inspect":
            guard let path = positionalPath(in: arguments) else {
                print("Usage: specimen-press inspect <font.ttf> [--json]")
                return
            }
            let font = try TrueTypeFont.load(from: URL(fileURLWithPath: path))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(font.summary)
            print(String(decoding: data, as: UTF8.self))
        case "render":
            guard let path = positionalPath(in: arguments) else {
                print("Usage: specimen-press render <font.ttf> [--output specimen.svg] [--sample TEXT]")
                return
            }
            let font = try TrueTypeFont.load(from: URL(fileURLWithPath: path))
            let output = optionValue("--output", in: arguments) ?? "SpecimenPress.svg"
            try write(
                renderer: SpecimenRenderer(),
                font: font,
                output: output,
                sampleText: optionValue("--sample", in: arguments)
            )
        case "help", "--help", "-h":
            print(usage)
        default:
            print(usage)
        }
    }

    private static func write(
        renderer: SpecimenRenderer,
        font: TrueTypeFont,
        output: String,
        sampleText: String?
    ) throws {
        let svg = renderer.render(font: font, sampleText: sampleText)
        try Data(svg.utf8).write(to: URL(fileURLWithPath: output))
        print("Wrote \(output)")
    }

    private static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func positionalPath(in arguments: [String]) -> String? {
        arguments.dropFirst().first { !$0.hasPrefix("--") }
    }

    private static let usage = """
    specimen-press inspect <font.ttf> [--json]
    specimen-press render <font.ttf> [--output specimen.svg] [--sample TEXT]
    specimen-press demo [--output specimen.svg] [--sample TEXT]
    """
}
