import SwiftUI

/// SPEC.md §7 — swipe-to-edit from Home. Revealing the existing value routes
/// through the same session gate as a normal Reveal (§2.2); in the common
/// case that's instant since opening Edit already required an unlocked
/// session, it only re-prompts if the session has since relocked.
struct EditVariableView: View {
    @EnvironmentObject private var store: QuickVarStore
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss

    let item: DecryptedIndexEntry

    @State private var name: String
    @State private var category: Category
    @State private var aliases: [String]
    @State private var newAlias = ""
    @State private var value = ""
    @State private var isValueLoaded = false
    @State private var isValueVisible = false
    @State private var expirationChoice: AddVariableView.ExpirationChoice
    @State private var customExpiresAt: Date
    @State private var deleteOnExpiration: Bool
    @State private var isEmergencyAccessible: Bool
    @State private var isPinned: Bool
    @State private var errorMessage: String?

    init(item: DecryptedIndexEntry) {
        self.item = item
        _name = State(initialValue: item.name)
        _category = State(initialValue: item.category ?? .other)
        _aliases = State(initialValue: item.aliases)
        if let expiresAt = item.expiresAt {
            _expirationChoice = State(initialValue: .custom)
            _customExpiresAt = State(initialValue: expiresAt)
        } else {
            _expirationChoice = State(initialValue: .never)
            _customExpiresAt = State(initialValue: Date().addingTimeInterval(60 * 60 * 24 * 30))
        }
        _deleteOnExpiration = State(initialValue: item.deleteOnExpiration)
        _isEmergencyAccessible = State(initialValue: item.isEmergencyAccessible)
        _isPinned = State(initialValue: item.isPinned)
    }

    private var resolvedExpiresAt: Date? {
        switch expirationChoice {
        case .never: return nil
        case .oneDay: return Date().addingTimeInterval(60 * 60 * 24)
        case .oneWeek: return Date().addingTimeInterval(60 * 60 * 24 * 7)
        case .custom: return customExpiresAt
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                }

                Section("Category") {
                    Picker(selection: $category) {
                        ForEach(Category.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.symbolName).tag(option)
                        }
                    } label: {
                        Label(category.label, systemImage: category.symbolName)
                    }
                }

                Section("Value") {
                    if isValueLoaded {
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
                    } else {
                        Button("Reveal to edit", action: revealForEditing)
                    }
                }

                Section("Aliases") {
                    ForEach(aliases, id: \.self) { alias in
                        Text(alias)
                    }
                    .onDelete { aliases.remove(atOffsets: $0) }

                    HStack {
                        TextField("Add alias", text: $newAlias)
                        Button("Add", action: addAlias)
                            .disabled(newAlias.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Expiration") {
                    Picker("Expires", selection: $expirationChoice) {
                        Text("Never").tag(AddVariableView.ExpirationChoice.never)
                        Text("In 1 Day").tag(AddVariableView.ExpirationChoice.oneDay)
                        Text("In 1 Week").tag(AddVariableView.ExpirationChoice.oneWeek)
                        Text("Custom Date").tag(AddVariableView.ExpirationChoice.custom)
                    }

                    if expirationChoice == .custom {
                        DatePicker("Date", selection: $customExpiresAt, displayedComponents: .date)
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
            .navigationTitle("Edit QuickVar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            // §2.3 — background locking dismisses any open Edit screen,
            // same safety net as RevealView.
            if !unlocked { dismiss() }
        }
    }

    private func addAlias() {
        let trimmed = newAlias.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        aliases.append(trimmed)
        newAlias = ""
    }

    private func revealForEditing() {
        Task {
            guard await session.requireUnlockedSession() else { return }
            do {
                value = try store.revealValue(id: item.id)
                isValueLoaded = true
            } catch {
                errorMessage = "Couldn't load the current value."
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !store.nameExists(trimmedName, excluding: item.id) else {
            errorMessage = "You already have a QuickVar named this."
            return
        }
        let fields = QuickVarFields(
            name: trimmedName,
            aliases: aliases,
            category: category,
            format: item.format,
            expiresAt: resolvedExpiresAt,
            deleteOnExpiration: expirationChoice != .never && deleteOnExpiration,
            isEmergencyAccessible: isEmergencyAccessible,
            isPinned: isPinned
        )
        do {
            try store.update(id: item.id, fields: fields, value: isValueLoaded ? value : nil)
            dismiss()
        } catch {
            errorMessage = "Couldn't save. Try again."
        }
    }
}
