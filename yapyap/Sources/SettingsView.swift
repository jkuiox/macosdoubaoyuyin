import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var showAccessKey = false
    @State private var testState: TestState = .idle
    @State private var micAuthorized = false
    @State private var accessibilityAuthorized = false

    /// When true, shows "Launch App" button and disables it until permissions are granted.
    var isStartup: Bool = false
    var onLaunch: (() -> Void)?

    private let permissionTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    enum TestState {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    private var allPermissionsGranted: Bool {
        micAuthorized && accessibilityAuthorized
    }

    var body: some View {
        Form {
            // Permissions section
            Section {
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

                Toggle(L10n.showMenuBarIcon, isOn: $store.showMenuBar)
                    .toggleStyle(.checkbox)

                // Launch button (startup mode only)
                if isStartup {
                    HStack {
                        Spacer()
                        Button(action: { onLaunch?() }) {
                            Text(L10n.launchApp)
                                .frame(minWidth: 120)
                        }
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!allPermissionsGranted)
                        Spacer()
                    }
                }
            } header: {
                Text(L10n.permissionsHeader)
            }

            // ASR API section
            Section {
                LabeledContent("App Key") {
                    TextField("", text: $store.appKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }

                LabeledContent("Access Key") {
                    HStack(spacing: 4) {
                        if showAccessKey {
                            TextField("", text: $store.accessKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("", text: $store.accessKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showAccessKey.toggle() }) {
                            Image(systemName: showAccessKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(width: 240)
                }

                Picker("Resource ID", selection: $store.resourceId) {
                    Text(L10n.resourceHourly20).tag("volc.seedasr.sauc.duration")
                    Text(L10n.resourceConcurrent20).tag("volc.seedasr.sauc.concurrent")
                    Text(L10n.resourceHourly10).tag("volc.bigasr.sauc.duration")
                    Text(L10n.resourceConcurrent10).tag("volc.bigasr.sauc.concurrent")
                }

                HStack {
                    Button(action: runTest) {
                        HStack(spacing: 4) {
                            if case .testing = testState {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(L10n.testConnection)
                        }
                    }
                    .disabled(store.appKey.isEmpty || store.accessKey.isEmpty || isTestRunning)

                    Spacer()

                    switch testState {
                    case .idle:
                        EmptyView()
                    case .testing:
                        Text(L10n.connecting)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .success(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    case .failure:
                        EmptyView()
                    }
                }

                if case .failure(let msg) = testState {
                    Text(msg)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.red.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            } header: {
                HStack {
                    Text(L10n.asrApiHeader)
                    Spacer()
                    Link(L10n.getKey, destination: URL(string: "https://console.volcengine.com/speech/service/10038")!)
                        .font(.callout)
                }
            }

            // Text processing sections
            Section {
                Picker("", selection: $store.punctuationMode) {
                    Text(L10n.keepOriginal).tag(PunctuationMode.keepOriginal)
                    Text(L10n.punctSpaceReplace).tag(PunctuationMode.spaceReplace)
                    Text(L10n.punctRemoveTrailing).tag(PunctuationMode.removeTrailing)
                    Text(L10n.punctKeepAll).tag(PunctuationMode.keepAll)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text(L10n.punctuationHeader)
            }

            Section {
                Picker("", selection: $store.englishSpacingMode) {
                    Text(L10n.keepOriginal).tag(EnglishSpacingMode.keepOriginal)
                    Text(L10n.spacingNone).tag(EnglishSpacingMode.noSpaces)
                    Text(L10n.spacingAdd).tag(EnglishSpacingMode.addSpaces)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text(L10n.spacingHeader)
            }

            Section {
                Picker("", selection: $store.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text(L10n.languageHeader)
            }

            Section {
                Text(L10n.usageText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(L10n.usageTip)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text(L10n.usageHeader)
            }

        }
        .formStyle(.grouped)
        .frame(width: 420, height: isStartup ? 700 : 640)
        .onAppear { checkPermissions() }
        .onReceive(permissionTimer) { _ in checkPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.accessibility.api"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                checkPermissions()
            }
        }
    }

    // MARK: - Permission rows

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
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(granted ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permissions

    private func checkPermissions() {
        micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAuthorized = isAccessibilityGranted()
    }

    private func isAccessibilityGranted() -> Bool {
        TextInjector.checkAccessibility(promptIfNeeded: false)
    }

    private func openMicrophoneSettings() {
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Test connection

    private var isTestRunning: Bool {
        if case .testing = testState { return true }
        return false
    }

    private func runTest() {
        testState = .testing
        ASRClient.testConnection(
            appKey: store.appKey,
            accessKey: store.accessKey,
            resourceId: store.resourceId
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let msg):
                    testState = .success(msg)
                case .failure(let error):
                    testState = .failure(error.localizedDescription)
                }
            }
        }
    }
}
