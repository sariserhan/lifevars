import SwiftUI

/// SPEC.md §6 — two-step wizard, not a single dense form. When opened from the
/// §1.4 first-QuickVar prompt, `prefillName` skips straight to step 2 with
/// classification already resolved.
struct AddVariableView: View {
    @EnvironmentObject private var store: QuickVarStore
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int
    @State private var name: String
    @State private var value = ""
    @State private var isValueVisible = false
    @State private var category: Category
    @State private var isCategoryManuallySet = false
    @State private var aliases: [String]
    @State private var format: ValueFormat?
    @State private var expirationChoice: ExpirationChoice = .never
    @State private var customExpiresAt = Date().addingTimeInterval(60 * 60 * 24 * 30)
    @State private var deleteOnExpiration = false
    @State private var isEmergencyAccessible = false
    @State private var isPinned = false
    @State private var errorMessage: String?
    @State private var isShowingPaywall = false

    private static let suggestions = [
        "Social Security Number", "Passport Number", "Driver's License",
        "VIN", "Insurance Policy", "Bank Account Number", "WiFi Password",
        "Electric Account", "EIN", "Membership Number", "Safe Combination", "Gate Code"
    ]

    enum ExpirationChoice: Hashable {
        case never, oneDay, oneWeek, custom
    }

    private var resolvedExpiresAt: Date? {
        switch expirationChoice {
        case .never: return nil
        case .oneDay: return Date().addingTimeInterval(60 * 60 * 24)
        case .oneWeek: return Date().addingTimeInterval(60 * 60 * 24 * 7)
        case .custom: return customExpiresAt
        }
    }

    init(prefillName: String? = nil) {
        if let prefillName, !prefillName.trimmingCharacters(in: .whitespaces).isEmpty {
            let resolved = Classification.classify(name: prefillName)
            _name = State(initialValue: prefillName)
            _category = State(initialValue: resolved.category)
            _aliases = State(initialValue: resolved.aliases)
            _format = State(initialValue: resolved.format)
            _step = State(initialValue: 2)
        } else {
            _name = State(initialValue: "")
            _category = State(initialValue: .other)
            _aliases = State(initialValue: [])
            _format = State(initialValue: nil)
            _step = State(initialValue: 1)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if step == 1 {
                    nameStep
                } else {
                    valueStep
                }
            }
            .navigationTitle("Add a QuickVar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    private var nameStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What do you want to remember?")
                    .font(.headline)
                TextField("e.g. Audi VIN", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(advance)

                Text("Suggestions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button {
                            name = suggestion
                            advance()
                        } label: {
                            Text(suggestion)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: advance)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding()
                .background(.bar)
        }
    }

    private func advance() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let resolved = Classification.classify(name: name)
        // Only auto-assign the category if the user hasn't already picked
        // one by hand — aliases stay tied to name-based classification
        // either way, since they're about likely phrasings, not category.
        if !isCategoryManuallySet {
            category = resolved.category
        }
        aliases = resolved.aliases
        format = resolved.format
        step = 2
    }

    /// A pick here always wins over auto-detection — even if the user
    /// later edits the name on this same screen, per §9.1's classifier only
    /// ever being a *default*.
    private var categoryBinding: Binding<Category> {
        Binding(
            get: { category },
            set: { newValue in
                category = newValue
                isCategoryManuallySet = true
            }
        )
    }

    /// Picking a quick preset (1 day / 1 week) defaults delete-on-expiration
    /// to on, since those presets are for disposable things like a hotel key
    /// code — but the user can still flip it back off underneath.
    private var expirationChoiceBinding: Binding<ExpirationChoice> {
        Binding(
            get: { expirationChoice },
            set: { newValue in
                expirationChoice = newValue
                if newValue == .oneDay || newValue == .oneWeek {
                    deleteOnExpiration = true
                }
            }
        )
    }

    private var valueStep: some View {
        Form {
            Section {
                Picker(selection: categoryBinding) {
                    ForEach(Category.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                } label: {
                    Label(category.label, systemImage: category.symbolName)
                }

                HStack {
                    Group {
                        if isValueVisible {
                            TextField("Value", text: $value)
                        } else {
                            SecureField("Value", text: $value)
                        }
                    }
                    .font(.system(.body, design: .monospaced))

                    Button {
                        isValueVisible.toggle()
                    } label: {
                        Image(systemName: isValueVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                TextField("Name", text: $name)
            }

            Section("Expiration") {
                Picker("Expires", selection: expirationChoiceBinding) {
                    Text("Never").tag(ExpirationChoice.never)
                    Text("In 1 Day").tag(ExpirationChoice.oneDay)
                    Text("In 1 Week").tag(ExpirationChoice.oneWeek)
                    Text("Custom Date").tag(ExpirationChoice.custom)
                }

                if expirationChoice == .custom {
                    DatePicker("Date", selection: $customExpiresAt, in: Date()..., displayedComponents: .date)
                }

                if expirationChoice != .never {
                    Toggle("Delete automatically when expired", isOn: $deleteOnExpiration)
                }
            }

            Section {
                Toggle("Emergency Access", isOn: $isEmergencyAccessible)
                if isEmergencyAccessible {
                    Text("Visible from the Lock Screen without Face ID — for things like blood type or an emergency contact. Don't use this for sensitive numbers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Pin to Lock Screen", isOn: $isPinned)
                if isPinned {
                    Text("Adds a shortcut widget to your Lock Screen. Only one QuickVar can be pinned — pinning this replaces any current pin. The widget itself never shows the name or value, only a generic locked icon; Face ID is still required to reveal it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || value.isEmpty)
                .padding()
                .background(.bar)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !store.nameExists(trimmedName) else {
            errorMessage = "You already have a QuickVar named this."
            return
        }
        // SPEC.md §6.2 — checked at Save, not at the "+" tap, so the compose
        // flow is never blocked before the user sees what they'd be saving.
        guard storeManager.isPro || store.items.count < StoreManager.freeItemLimit else {
            isShowingPaywall = true
            return
        }
        let fields = QuickVarFields(
            name: trimmedName,
            aliases: aliases,
            category: category,
            format: format,
            expiresAt: resolvedExpiresAt,
            deleteOnExpiration: expirationChoice != .never && deleteOnExpiration,
            isEmergencyAccessible: isEmergencyAccessible,
            isPinned: isPinned
        )
        do {
            try store.add(fields, value: value)
            dismiss()
        } catch {
            errorMessage = "Couldn't save. Try again."
        }
    }
}
