import Foundation

/// SPEC.md §9.1 — local, deterministic keyword lookup, first match wins. No
/// network call, no ML model. Mechanical aliasing only applies when a name
/// hits a known category here — unclassified names get .other with no
/// aliases (§9.1's conservative revision), rather than guessed phrasings.
/// This result is only ever used as the *default* — Add/Edit let the user
/// override it directly, at which point this function's opinion is ignored.
enum Classification {
    private static let rules: [(keywords: [String], category: Category, aliases: [String], format: ValueFormat?)] = [
        (["vin", "vehicle number"], .vehicle, ["VIN", "Car VIN", "Vehicle VIN"], nil),
        (["ein", "employer id"], .business, ["EIN", "Tax ID"], .ein),
        (["ssn", "social security"], .identity, ["SSN", "Social"], .ssn),
        (["passport"], .identity, ["Passport", "Passport Number"], nil),
        (["electric account", "power account"], .home, ["Electric", "Power Account"], nil),
        (["hvac filter", "air filter"], .home, ["Filter Size", "Air Filter"], nil)
    ]

    static func classify(name: String) -> (category: Category, aliases: [String], format: ValueFormat?) {
        let normalized = name.lowercased()
        for rule in rules where rule.keywords.contains(where: { normalized.contains($0) }) {
            return (rule.category, rule.aliases, rule.format)
        }
        return (.other, [], nil)
    }
}
