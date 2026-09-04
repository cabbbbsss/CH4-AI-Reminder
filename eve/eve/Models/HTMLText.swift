//
//  HTMLText.swift
//  Eve
//

import Foundation

/// Converts HTML-ish rich text into clean plain text. Some calendars (and
/// shared reminder lists) store notes as HTML, which otherwise shows up as
/// raw `<ul><li>…</li></ul>` in the UI and as markup noise in the prompt.
///
/// Deliberately regex-based, NOT `NSAttributedString(html:)` / WebKit: this
/// text is attacker-reachable (anyone who can send the user an invite writes
/// it — see `UntrustedText`), and an HTML parser that can fetch remote
/// resources or run scripts is the wrong tool for untrusted input. This does
/// no I/O and is fully deterministic.
enum HTMLText {

    /// Returns plain text when `html` actually contains markup or entities,
    /// otherwise the original string unchanged. nil / empty pass through.
    static func plainIfNeeded(_ html: String?) -> String? {
        guard let html, !html.isEmpty else { return html }
        guard html.contains("<") || html.contains("&") else { return html }
        let cleaned = plain(html)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func plain(_ html: String) -> String {
        var s = html

        // Block / list structure → readable line breaks and bullets.
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</ul>", "</ol>", "</tr>"] {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<li>", with: "\n• ", options: .caseInsensitive)

        // Remove every remaining tag.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Common named entities.
        let named = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}"
        ]
        for (entity, character) in named {
            s = s.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }

        // Decimal numeric entities (&#8217; etc.).
        s = decodeNumericEntities(s)

        // Collapse the whitespace the markup left behind.
        s = s.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(\\d+);") else { return text }
        let ns = text as NSString
        var result = text

        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let numberRange = match.range(at: 1)
            guard numberRange.location != NSNotFound,
                  let code = UInt32(ns.substring(with: numberRange)),
                  let scalar = Unicode.Scalar(code) else { continue }
            result = result.replacingOccurrences(
                of: ns.substring(with: match.range),
                with: String(scalar)
            )
        }

        return result
    }
}
