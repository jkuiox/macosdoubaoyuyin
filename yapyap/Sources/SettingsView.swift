import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var showAccessKey = false

    var body: some View {
        Form {
            Section {
                TextField("App Key", text: $store.appKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if showAccessKey {
                        TextField("Access Key", text: $store.accessKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Access Key", text: $store.accessKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showAccessKey.toggle() }) {
                        Image(systemName: showAccessKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Picker("Resource ID", selection: $store.resourceId) {
                    Text("2.0 小时版").tag("volc.seedasr.sauc.duration")
                    Text("2.0 并发版").tag("volc.seedasr.sauc.concurrent")
                    Text("1.0 小时版").tag("volc.bigasr.sauc.duration")
                    Text("1.0 并发版").tag("volc.bigasr.sauc.concurrent")
                }
            } header: {
                Text("豆包 ASR API")
            }

            Section {
                Text("Hold **fn** key to start recording.\nRelease to stop and insert text at cursor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Tip: In System Settings → Keyboard, set \"Press 🌐 key to\" → \"Do Nothing\" for best experience.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("Usage")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
    }
}
