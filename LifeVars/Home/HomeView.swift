import SwiftUI

/// SPEC.md §3 — the index. Values are never shown here, even after auth; a
/// row tap presents RevealView, which does the session gate + decrypt itself.
struct HomeView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var store: LifeVarStore
    @StateObject private var voiceRecognizer = VoiceRecognizer()

    @AppStorage(UserSettings.Keys.hasSeenFirstLifeVarPrompt) private var hasSeenFirstPrompt = false
    @State private var firstPromptName = ""

    @State private var searchText = ""
    @State private var isAdding = false
    @State private var addPrefillName: String?
    @State private var editingItem: DecryptedIndexEntry?
    @State private var revealingItem: DecryptedIndexEntry?
    @State private var disambiguation: DisambiguationQuery?
    @State private var isShowingSettings = false
    @AppStorage("groupByCategory") private var groupByCategory = false

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty && !hasSeenFirstPrompt {
                    firstLifeVarPrompt
                } else if store.items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("LifeVars")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        session.lock()
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addPrefillName = nil
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isAdding) {
            AddVariableView(prefillName: addPrefillName)
        }
        .sheet(item: $editingItem) { item in
            EditVariableView(item: item)
        }
        .fullScreenCover(item: $revealingItem) { item in
            RevealView(item: item)
        }
        .sheet(item: $disambiguation) { query in
            DisambiguationView(query: query) { chosen in
                disambiguation = nil
                revealingItem = chosen
            }
        }
        // SPEC.md §13 — covers both cold launch (onAppear, once Home shows
        // post-unlock) and the app already being open when Siri/a widget
        // hands off a query (didBecomeActive, since openAppWhenRun and a
        // widget tap both just foreground the app).
        .onAppear(perform: checkPendingActions)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            checkPendingActions()
        }
    }

    // MARK: - List + search

    /// SPEC.md §9.2 — the same matcher voice will use in step 9. Empty query
    /// falls back to the full recency-sorted list (no filtering to apply).
    private var filteredItems: [DecryptedIndexEntry] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return store.items }
        return Matcher.match(query: searchText, in: store.items).map(\.entry)
    }

    private struct CategorySection: Identifiable {
        let category: Category
        let items: [DecryptedIndexEntry]
        var id: Category { category }
    }

    /// Groups the already-filtered/searched results, not the raw store — so
    /// search and grouping compose. Ordered by `Category.allCases`, skipping
    /// any category with nothing in it right now (no empty section headers).
    private var groupedSections: [CategorySection] {
        let grouped = Dictionary(grouping: filteredItems) { $0.category ?? .other }
        return Category.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return CategorySection(category: category, items: items)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            searchField
            groupToggle
            if filteredItems.isEmpty {
                noMatchState
            } else {
                List {
                    if groupByCategory {
                        ForEach(groupedSections) { section in
                            Section(section.category.label.uppercased()) {
                                ForEach(section.items) { item in
                                    row(for: item)
                                }
                            }
                        }
                    } else {
                        Section("YOUR VARIABLES") {
                            ForEach(filteredItems) { item in
                                row(for: item)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var groupToggle: some View {
        HStack {
            Spacer()
            Button {
                groupByCategory.toggle()
            } label: {
                Label(
                    "Category",
                    systemImage: groupByCategory ? "checkmark.circle.fill" : "circle"
                )
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if voiceRecognizer.state == .listening {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(voiceRecognizer.transcript.isEmpty ? "Listening..." : voiceRecognizer.transcript)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                } else {
                    TextField("Search or ask...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit {
                            // §3.2 — narrowing to exactly one row and hitting
                            // Return reveals it, same as a tap.
                            if filteredItems.count == 1 {
                                revealingItem = filteredItems.first
                            }
                        }
                }

                Button(action: toggleMic) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(voiceRecognizer.state == .listening ? .red : .secondary)
                }
                .disabled(isVoiceUnavailable)
            }

            if case .unavailable(let reason) = voiceRecognizer.state {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var isVoiceUnavailable: Bool {
        if case .unavailable = voiceRecognizer.state { return true }
        return false
    }

    private func toggleMic() {
        switch voiceRecognizer.state {
        case .idle:
            voiceRecognizer.start(onFinish: handleVoiceResult)
        case .listening:
            voiceRecognizer.stopManually()
        case .unavailable:
            break
        }
    }

    /// Drains every widget/Siri handoff — by the time any of these run, the
    /// user has already gone through the normal session gate to see Home at
    /// all (§2, §13).
    private func checkPendingActions() {
        checkPendingSiriQuery()
        checkPendingReveal()
        checkPendingVoiceActivation()
    }

    private func checkPendingSiriQuery() {
        guard let query = PendingSiriQuery.shared.query else { return }
        PendingSiriQuery.shared.query = nil
        handleVoiceResult(query)
    }

    /// Widgets/PinnedVariableWidget.swift's Lock Screen tap target — the
    /// widget itself never held anything but this id (§ Widgets).
    private func checkPendingReveal() {
        guard let id = PendingDeepLink.shared.revealItemID else { return }
        PendingDeepLink.shared.revealItemID = nil
        revealingItem = store.items.first(where: { $0.id == id })
    }

    /// Widgets/AskLifeVarsControl.swift's Control Center control.
    private func checkPendingVoiceActivation() {
        guard WidgetBridge.consumePendingActivateVoice() else { return }
        guard voiceRecognizer.state == .idle else { return }
        toggleMic()
    }

    /// SPEC.md §4 — single confident match reveals immediately (no
    /// intermediate screen), multiple matches go to disambiguation (§10),
    /// no match reuses the typed-search no-match card with the transcript
    /// pre-filled as the name.
    private func handleVoiceResult(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let matches = Matcher.match(query: trimmed, in: store.items)
        guard let topConfidence = matches.first?.confidence else {
            searchText = trimmed
            return
        }
        let topMatches = matches.filter { $0.confidence == topConfidence }.map(\.entry)
        if topMatches.count == 1 {
            revealingItem = topMatches[0]
        } else {
            let heading = Matcher.normalize(trimmed).capitalized
            disambiguation = DisambiguationQuery(heading: "Which \(heading)?", candidates: topMatches)
        }
    }

    private func row(for item: DecryptedIndexEntry) -> some View {
        Button {
            revealingItem = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: (item.category ?? .other).symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    // §14 — VoiceOver would otherwise read every dot as the
                    // literal word "bullet"; hide the decoration and give
                    // the row one sensible combined label instead.
                    Text(String(repeating: "•", count: 12))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), hidden value")
        .swipeActions {
            Button("Delete", role: .destructive) {
                try? store.delete(id: item.id)
            }
            Button("Edit") {
                editingItem = item
            }
            .tint(.blue)
        }
    }

    /// SPEC.md §3.2 — typed query with no match, offered as a new LifeVar name.
    private var noMatchState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("No match for \u{201C}\(searchText)\u{201D}")
                .foregroundStyle(.secondary)
            Button("Save \u{201C}\(searchText)\u{201D} as new") {
                addPrefillName = searchText
                isAdding = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("{ = }")
                .font(.system(size: 40, weight: .light, design: .monospaced))
            Text("Nothing to remember yet.")
                .font(.headline)
            Text("Add the numbers and details you never want to look up again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Add a LifeVar") {
                addPrefillName = nil
                isAdding = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// SPEC.md §1.4 — shown once, immediately after onboarding, in place of
    /// the recurring empty state above.
    private var firstLifeVarPrompt: some View {
        VStack(spacing: 16) {
            Text("What's something you\nalways forget?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            TextField("e.g. Audi VIN", text: $firstPromptName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
                .onSubmit(startAddingFromPrompt)
            Button("Continue", action: startAddingFromPrompt)
                .buttonStyle(.borderedProminent)
                .disabled(firstPromptName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Skip for now") {
                hasSeenFirstPrompt = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func startAddingFromPrompt() {
        guard !firstPromptName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        hasSeenFirstPrompt = true
        addPrefillName = firstPromptName
        isAdding = true
    }
}
