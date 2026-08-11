import SwiftUI
import UniformTypeIdentifiers

/// SPEC.md §5 — full-screen cover. Auth happens on appear via the same
/// session gate as everything else (§2.2) — instant if already unlocked.
///
/// On timeout, re-masks in place with "Reveal Again" rather than dismissing —
/// backgrounding (§2.3), not this countdown, is the real security boundary.
struct RevealView: View {
    let item: DecryptedIndexEntry

    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var store: QuickVarStore
    @Environment(\.dismiss) private var dismiss

    @State private var value: String?
    @State private var remainingSeconds = UserSettings.autoHideSeconds
    @State private var isRecording = UIScreen.main.isCaptured
    @State private var errorMessage: String?
    @State private var justCopied = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: (item.category ?? .other).symbolName)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(item.name)
                .font(.title2.bold())

            valueArea

            if value != nil, !isRecording {
                Button(justCopied ? "Copied" : "Copy", action: copy)
                    .buttonStyle(.borderedProminent)
            }

            footer

            if let expiresAt = item.expiresAt {
                Text(item.deleteOnExpiration ? "Deletes \(expiresAt.formatted(date: .abbreviated, time: .omitted))" : "Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .onAppear(perform: reveal)
        .onReceive(timer) { _ in tick() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isRecording = UIScreen.main.isCaptured
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            // §2.3 — backgrounding clears the session; this view shouldn't outlive it.
            if !unlocked { dismiss() }
        }
    }

    @ViewBuilder
    private var valueArea: some View {
        if isRecording {
            Text("Value hidden while screen recording is active.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        } else if let value {
            // Cosmetic only — Copy still copies the raw stored value below.
            Text(item.format?.apply(to: value) ?? value)
                .font(.system(.title3, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 24)
        } else if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            // §14 — same VoiceOver fix as Home's row: don't read the mask
            // literally.
            Text(String(repeating: "•", count: 17))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Value hidden")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if value != nil {
            Text("Hides in \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if errorMessage == nil {
            Button("Reveal Again", action: reveal)
                .buttonStyle(.bordered)
        }
    }

    private func reveal() {
        Task {
            guard await session.requireUnlockedSession() else { return }
            do {
                value = try store.revealValue(id: item.id)
                remainingSeconds = UserSettings.autoHideSeconds
            } catch {
                errorMessage = "Couldn't reveal this value."
            }
        }
    }

    private func tick() {
        guard value != nil else { return }
        guard remainingSeconds > 1 else {
            value = nil
            return
        }
        remainingSeconds -= 1
    }

    /// SPEC.md §5 — native UIPasteboard expiration, not a custom timer.
    private func copy() {
        guard let value else { return }
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }
}
