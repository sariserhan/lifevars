import SwiftUI

/// SPEC.md §11 — deliberately small.
struct SettingsView: View {
    @EnvironmentObject private var store: LifeVarStore
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UserSettings.Keys.biometricEnabled) private var biometricEnabled = false
    @AppStorage(UserSettings.Keys.unlockMethod) private var unlockMethodRaw = UnlockMethod.faceIDOnly.rawValue
    @AppStorage(UserSettings.Keys.lockOnBackground) private var lockOnBackground = true
    @AppStorage(UserSettings.Keys.autoHideSeconds) private var autoHideSeconds = 30
    @AppStorage(UserSettings.Keys.appearance) private var appearanceRaw = AppearanceOption.system.rawValue

    @State private var isShowingPaywall = false
    @State private var isShowingExportBackup = false
    @State private var isShowingRestoreBackup = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    if biometricEnabled {
                        Picker("Unlock Method", selection: $unlockMethodRaw) {
                            Text("Face ID Only").tag(UnlockMethod.faceIDOnly.rawValue)
                            Text("Face ID + Passcode").tag(UnlockMethod.faceIDOrPasscode.rawValue)
                        }
                        // §2.4 — the trade-off has to be visible at the point
                        // of choice, not buried.
                        if unlockMethodRaw == UnlockMethod.faceIDOnly.rawValue {
                            Text("If your Face ID settings change, your LifeVars cannot be recovered.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Auto-hide", selection: $autoHideSeconds) {
                        Text("10 seconds").tag(10)
                        Text("20 seconds").tag(20)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }

                    Toggle("Lock when app backgrounds", isOn: $lockOnBackground)
                }

                Section("LifeVars Pro") {
                    if storeManager.isPro {
                        Text("Pro — Unlimited")
                    } else {
                        Button {
                            isShowingPaywall = true
                        } label: {
                            HStack {
                                Text("\(store.items.count) of \(StoreManager.freeItemLimit) used")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Upgrade →")
                            }
                        }
                    }
                }

                Section {
                    Button("Export Encrypted Backup") {
                        if storeManager.isPro {
                            isShowingExportBackup = true
                        } else {
                            isShowingPaywall = true
                        }
                    }
                    Button("Restore from Backup") {
                        if storeManager.isPro {
                            isShowingRestoreBackup = true
                        } else {
                            isShowingPaywall = true
                        }
                    }
                } footer: {
                    Text("A password-protected file you save yourself — nothing is uploaded automatically. You'll need the password again to restore it.")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearanceOption.allCases, id: \.rawValue) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("About") {
                    NavigationLink("How It Works") { HowItWorksView() }
                    NavigationLink("Privacy") { PrivacyInfoView() }
                    NavigationLink("Security") { SecurityInfoView() }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $isShowingExportBackup) {
            ExportBackupView()
        }
        .sheet(isPresented: $isShowingRestoreBackup) {
            RestoreBackupView()
        }
    }
}
