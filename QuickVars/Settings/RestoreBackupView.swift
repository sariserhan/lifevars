import SwiftUI
import UniformTypeIdentifiers

/// Adds every item in the backup as new — see QuickVarStore.importBackupItems().
struct RestoreBackupView: View {
    @EnvironmentObject private var store: QuickVarStore
    @Environment(\.dismiss) private var dismiss

    @State private var isPickingFile = false
    @State private var pickedFileData: Data?
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isRestoring = false
    @State private var restoredCount: Int?

    var body: some View {
        NavigationStack {
            Form {
                if let restoredCount {
                    Section {
                        Text("Restored \(restoredCount) QuickVar\(restoredCount == 1 ? "" : "s").")
                            .foregroundStyle(.secondary)
                    }
                } else if pickedFileData == nil {
                    Section {
                        Button("Choose Backup File") {
                            isPickingFile = true
                        }
                    } footer: {
                        Text("Pick a file created with QuickVars' Export Encrypted Backup.")
                    }
                } else {
                    Section {
                        SecureField("Backup password", text: $password)
                    } footer: {
                        Text("Restoring adds these as new QuickVars — it won't overwrite or remove anything already here.")
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

                    Section {
                        Button {
                            restore()
                        } label: {
                            if isRestoring {
                                ProgressView()
                            } else {
                                Text("Restore")
                            }
                        }
                        .disabled(password.isEmpty || isRestoring)
                    }
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(restoredCount == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url):
                    loadFile(at: url)
                case .failure:
                    errorMessage = "Couldn't read that file."
                }
            }
        }
    }

    private func loadFile(at url: URL) {
        errorMessage = nil
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't read that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            pickedFileData = try Data(contentsOf: url)
        } catch {
            errorMessage = "Couldn't read that file."
        }
    }

    private func restore() {
        guard let pickedFileData else { return }
        errorMessage = nil
        isRestoring = true
        Task {
            do {
                let items = try BackupCodec.decrypt(data: pickedFileData, password: password)
                try store.importBackupItems(items)
                restoredCount = items.count
            } catch {
                errorMessage = "Wrong password, or that file isn't a valid QuickVars backup."
            }
            isRestoring = false
        }
    }
}
