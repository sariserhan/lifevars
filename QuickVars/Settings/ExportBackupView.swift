import SwiftUI

/// The one place a password (not Face ID) protects something in QuickVars —
/// necessary because a backup file has to be openable on a different
/// device or after a reinstall, where the device-only DEK doesn't exist.
struct ExportBackupView: View {
    @EnvironmentObject private var store: QuickVarStore
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var exportedFileURL: URL?

    private var canExport: Bool {
        password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                if let exportedFileURL {
                    Section {
                        Text("Backup ready. Save it somewhere safe — you'll need the password you just set to restore it. There's no way to recover it without that password.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ShareLink(item: exportedFileURL) {
                            Label("Save Backup File", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section {
                        SecureField("Backup password", text: $password)
                        SecureField("Confirm password", text: $confirmPassword)
                    } footer: {
                        Text("This password protects the exported file only — it's separate from Face ID and never leaves this device. At least 8 characters. Write it down; there's no way to recover a backup without it.")
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

                    Section {
                        Button {
                            export()
                        } label: {
                            if isExporting {
                                ProgressView()
                            } else {
                                Text("Export Encrypted Backup")
                            }
                        }
                        .disabled(!canExport || isExporting)
                    }
                }
            }
            .navigationTitle("Export Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func export() {
        errorMessage = nil
        isExporting = true
        Task {
            do {
                let items = try store.exportBackupItems()
                let data = try BackupCodec.encrypt(items: items, password: password)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("QuickVars-Backup-\(Int(Date().timeIntervalSince1970))")
                    .appendingPathExtension("quickvarsbackup")
                try data.write(to: url, options: .atomic)
                exportedFileURL = url
            } catch {
                errorMessage = "Couldn't create the backup. Try again."
            }
            isExporting = false
        }
    }
}
