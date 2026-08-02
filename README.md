# Specimen Press

Specimen Press inspects TrueType fonts and turns glyph outlines into readable SVG specimen sheets.

It exposes one Swift library and one command-line tool.

## Value

Use it when a font needs a compact, repeatable inspection artifact.

The output shows glyph coverage, font metrics, baselines, and decoded outline paths.

The bundled fixture makes the demo and tests run without network access or secrets.

## Capabilities

- Parse head, cmap, hmtx, and glyf tables.
- Read loca, maxp, hhea, and optional name data.
- Decode simple and composite glyph outlines.
- Report metrics and Unicode coverage as FontSummary.
- Render an SVG specimen sheet for a TrueType font.
- Draw sample text, metric lines, and an uppercase glyph grid.

## Architecture

BinaryReader reads big-endian values with bounds checks.

TrueTypeFont validates the table directory and coordinates table parsing.

GlyphDecoder expands simple contours and composite components.

SpecimenRenderer maps outlines into a stable SVG layout.

The CLI keeps file access and output formatting outside the library.

## Setup

Install Swift 5.9 or newer.

Clone the repository.

Run the bundled demo.

~~~sh
swift run specimen-press demo --output specimen.svg
~~~

Open specimen.svg in a browser or vector editor.

Inspect any TrueType font.

~~~sh
swift run specimen-press inspect /path/to/font.ttf
~~~

Render a custom sheet.

~~~sh
swift run specimen-press render /path/to/font.ttf   --output specimen.svg   --sample "A SHORT FONT SAMPLE"
~~~

Run tests and a release build.

~~~sh
swift test
swift build -c release
~~~

## Sample output

The bundled fixture reports stable values.

~~~json
{
  "familyName" : "Specimen Press",
  "mappedCodePointCount" : 27,
  "metrics" : {
    "ascender" : 800,
    "descender" : -200,
    "lineGap" : 200,
    "numberOfGlyphs" : 28,
    "numberOfHorizontalMetrics" : 28,
    "unitsPerEm" : 1000
  }
}
~~~

The demo writes one SVG file.

~~~text
Wrote specimen.svg
~~~

## Tests

Tests assert fixture metrics, coverage ranges, glyph outlines, SVG labels, and malformed input handling.

Local status: not run because Swift is unavailable in the supplied Windows environment.

CI runs swift test, a release build, and the bundled demo on macOS.

## Limitations

- The first release supports TrueType outlines in glyf.
- It does not parse CFF or CFF2 outlines.
- It reads cmap formats 4 and 12.
- It does not execute TrueType hinting instructions.
- It renders uppercase A-Z cells and uses glyph zero for missing sample characters.
- It inspects one font file at a time.
- It does not subset, edit, or write font files.

## Roadmap

1. Add CFF and CFF2 outline inspection.
2. Add kerning and variable-font axis summaries.
3. Add optional JSON and SVG snapshot fixtures.
4. Add contour winding diagnostics.

## License

The library and CLI use the MIT License.

The bundled fixture uses the CC0 1.0 Universal dedication in FONT-LICENSE.txt.
