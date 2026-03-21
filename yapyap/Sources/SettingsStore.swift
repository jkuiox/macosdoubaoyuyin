import Foundation

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var appKey: String {
        didSet { UserDefaults.standard.set(appKey, forKey: "appKey") }
    }
    @Published var accessKey: String {
        didSet { UserDefaults.standard.set(accessKey, forKey: "accessKey") }
    }
    @Published var resourceId: String {
        didSet { UserDefaults.standard.set(resourceId, forKey: "resourceId") }
    }

    private init() {
        self.appKey = UserDefaults.standard.string(forKey: "appKey") ?? ""
        self.accessKey = UserDefaults.standard.string(forKey: "accessKey") ?? ""
        self.resourceId = UserDefaults.standard.string(forKey: "resourceId") ?? "volc.seedasr.sauc.duration"
    }
}
