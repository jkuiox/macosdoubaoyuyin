import SwiftUI
import AVFoundation
import AppKit

struct StartupDialog: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var micAuthorized = false
    @State private var accessibilityAuthorized = false
    var onLaunch: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var allPermissionsGranted: Bool {
        micAuthorized && accessibilityAuthorized
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("yapyap")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.top, 24)
                .padding(.bottom, 8)

            // Menu bar toggle
            Toggle(L10n.showMenuBarIcon, isOn: $store.showMenuBar)
                .toggleStyle(.checkbox)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 24)

            // Permissions section
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.permissionsHeader)
                    .font(.headline)
                    .padding(.bottom, 4)

                permissionRow(
                    name: L10n.micPermission,
                    description: L10n.micDescription,
                    granted: micAuthorized,
                    action: openMicrophoneSettings
                )

                permissionRow(
                    name: L10n.accessibilityPermission,
                    description: L10n.accessibilityDescription,
                    granted: accessibilityAuthorized,
                    action: openAccessibilitySettings
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()

            // Launch button
            Button(action: onLaunch) {
                Text(L10n.launchApp)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!allPermissionsGranted)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 350)
        .onAppear { checkPermissions() }
        .onReceive(timer) { _ in checkPermissions() }
    }

    private func permissionRow(name: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(granted ? .green : .red)
                    .frame(width: 24)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Text(granted ? L10n.permissionGranted : L10n.permissionNotGranted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !granted {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(granted ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private func checkPermissions() {
        micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAuthorized = AXIsProcessTrusted()
    }

    private func openMicrophoneSettings() {
        // Trigger the system permission prompt if not yet determined
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.micAuthorized = granted
                }
            }
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func openAccessibilitySettings() {
        // Trigger the system permission prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
