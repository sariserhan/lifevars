import SwiftUI

/// "Insurance policy." → Watch relays the query to the phone (the phone's
/// already-unlocked session does the real work) → answer or a clear reason
/// why not. No scrolling, no folders — matches the product's Apple Watch
/// concept: retrieving one tiny fact, fast.
struct ContentView: View {
    @StateObject private var connectivity = WatchConnectivityManager()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                switch connectivity.state {
                case .idle:
                    askView
                case .asking:
                    ProgressView("Asking…")
                case .result(let name, let value):
                    resultView(name: name, value: value)
                case .locked:
                    messageView("Open LifeVars on iPhone first.", systemImage: "iphone")
                case .notFound:
                    messageView("No match for that.", systemImage: "questionmark.circle")
                case .ambiguous(let names):
                    ambiguousView(names)
                case .unreachable:
                    messageView("iPhone not nearby.", systemImage: "iphone.slash")
                case .error:
                    messageView("Couldn't reach iPhone.", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("LifeVars")
        }
    }

    private var askView: some View {
        VStack(spacing: 8) {
            Text("{ = }")
                .font(.system(size: 24, weight: .light, design: .monospaced))
            TextField("Ask…", text: $query)
                .onSubmit(ask)
            Button("Ask", action: ask)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func resultView(name: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(name.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
            Button("Done", action: done)
        }
    }

    private func ambiguousView(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Which one?")
                .font(.headline)
            ForEach(names, id: \.self) { name in
                Button(name) {
                    query = name
                    ask()
                }
            }
        }
    }

    private func messageView(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("OK", action: done)
        }
    }

    private func ask() {
        connectivity.ask(query)
    }

    private func done() {
        connectivity.reset()
        query = ""
    }
}
