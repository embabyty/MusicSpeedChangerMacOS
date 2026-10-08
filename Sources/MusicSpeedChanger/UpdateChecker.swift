import Foundation
import AppKit
import MSCCore

/// Update checks against this project's GitHub Releases
/// (same feed shape as the Windows build).
@MainActor
enum UpdateChecker {
    struct Release {
        let version: String
        let notes: String
        let htmlURL: String?
    }

    enum Outcome {
        case upToDate(current: String)
        case available(Release)
        case failed(String)
    }

    /// Current bundle version, nil for version-less dev builds.
    static var currentVersion: String? {
        guard let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !v.isEmpty
        else { return nil }
        return v
    }

    /// One-shot check used by Settings → Check now.
    static func check(feed: String) async -> Outcome {
        let current = currentVersion ?? "development build"
        guard let url = URL(string: feed.trimmingCharacters(in: .whitespaces)), !feed.isEmpty else {
            return .failed("The update feed URL is empty.")
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String
            else {
                // No releases published yet (GitHub returns 404 "Not Found" JSON).
                return .upToDate(current: current)
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard let current = currentVersion else {
                // Dev build: report what's out there without claiming an update.
                return .available(Release(version: version,
                                          notes: obj["body"] as? String ?? "",
                                          htmlURL: obj["html_url"] as? String))
            }
            if compare(version, isNewerThan: current) {
                return .available(Release(version: version,
                                          notes: obj["body"] as? String ?? "",
                                          htmlURL: obj["html_url"] as? String))
            }
            return .upToDate(current: current)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static var checked = false

    /// Startup check: silent for version-less dev builds.
    static func checkIfNewer() {
        guard !checked else { return }
        checked = true
        guard currentVersion != nil else { return }
        let feed = AppSettings.load().updateFeedUrl
        Task {
            let outcome = await check(feed: feed)
            if case .available(let release) = outcome {
                prompt(tag: release.version, htmlURL: release.htmlURL)
            }
        }
    }

    private static func compare(_ a: String, isNewerThan b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    static func prompt(tag: String, htmlURL: String?) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version of Music Speed Changer (\(tag)) is available."
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let htmlURL, let url = URL(string: htmlURL)
        {
            NSWorkspace.shared.open(url)
        }
    }
}
