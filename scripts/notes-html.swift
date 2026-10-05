// Turns a release-notes file (docs/release-notes/<version>.md) into the small HTML page
// Sparkle shows in its update window. Handles what release notes need: paragraphs,
// "- " bullet lists, "## " headings, and inline **bold**, *italic*, `code` and links.
//
// Run with: swift scripts/notes-html.swift docs/release-notes/1.0.1.md
import Foundation

func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

/// Inline Markdown to HTML, using Foundation's own Markdown parser.
func inline(_ markdown: String) -> String {
    guard let parsed = try? AttributedString(
        markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    else { return escape(markdown) }
    var html = ""
    for run in parsed.runs {
        var text = escape(String(parsed[run.range].characters))
        let intent = run.inlinePresentationIntent ?? []
        if intent.contains(.code) { text = "<code>\(text)</code>" }
        if intent.contains(.emphasized) { text = "<em>\(text)</em>" }
        if intent.contains(.stronglyEmphasized) { text = "<strong>\(text)</strong>" }
        if let link = run.link { text = "<a href=\"\(escape(link.absoluteString))\">\(text)</a>" }
        html += text
    }
    return html
}

let path = CommandLine.arguments.dropFirst().first ?? ""
guard let markdown = try? String(contentsOfFile: path, encoding: .utf8) else {
    FileHandle.standardError.write("Usage: swift scripts/notes-html.swift <notes.md>\n".data(using: .utf8)!)
    exit(1)
}

var body = ""
var inList = false
for rawLine in markdown.components(separatedBy: .newlines) {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("- ") {
        if !inList { body += "<ul>\n"; inList = true }
        body += "<li>\(inline(String(line.dropFirst(2))))</li>\n"
        continue
    }
    if inList { body += "</ul>\n"; inList = false }
    if line.hasPrefix("## ") {
        body += "<h3>\(inline(String(line.dropFirst(3))))</h3>\n"
    } else if !line.isEmpty {
        body += "<p>\(inline(line))</p>\n"
    }
}
if inList { body += "</ul>\n" }

// A solid background in both appearances, in the system font, so the notes read like
// part of the app rather than a web page.
print("""
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
:root { color-scheme: light dark; }
html, body { background: #ffffff; color: #1d1d1f; }
body { font: 13px/1.45 -apple-system, BlinkMacSystemFont, sans-serif; margin: 12px 16px; }
h3 { font-size: 13px; margin: 14px 0 6px; }
p { margin: 0 0 10px; }
ul { margin: 0 0 10px; padding-left: 20px; }
li { margin: 0 0 6px; }
code { font: 12px ui-monospace, Menlo, monospace; background: #f0f0f3; padding: 1px 4px; border-radius: 4px; }
a { color: #0a64d8; }
@media (prefers-color-scheme: dark) {
  html, body { background: #1e1e1e; color: #f2f2f4; }
  code { background: #333336; }
  a { color: #4ea1ff; }
}
</style></head>
<body>
\(body)</body></html>
""")
