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
        (["driver's license", "drivers license"], .identity, ["Driver's License", "DL Number"], nil),
        (["insurance"], .insurance, ["Insurance", "Policy Number"], nil),
        (["bank account"], .financial, ["Bank Account", "Account Number"], nil),
        (["membership"], .membership, ["Membership Number", "Member ID"], nil),
        (["electric account", "power account"], .home, ["Electric", "Power Account"], nil),
        (["hvac filter", "air filter"], .home, ["Filter Size", "Air Filter"], nil),
        (["wifi", "wi-fi", "router"], .home, ["WiFi Password", "Router Password"], nil),
        (["safe combination", "safe code"], .home, ["Safe Combination"], nil),
        (["gate code"], .home, ["Gate Code"], nil)
    ]

    static func classify(name: String) -> (category: Category, aliases: [String], format: ValueFormat?) {
        let normalized = name.lowercased()
        for rule in rules where rule.keywords.contains(where: { normalized.contains($0) }) {
            return (rule.category, rule.aliases, rule.format)
        }
        return (.other, [], nil)
    }
}
