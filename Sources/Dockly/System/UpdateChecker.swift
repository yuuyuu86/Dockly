import Foundation
import Combine
import AppKit

/// In-app updates.
///
/// Dockly reads a small JSON appcast, compares it with the running build, and
/// hands the download to the user. It never swaps the app bundle out from
/// under a running process — the download is revealed in Finder and the user
/// installs it, which keeps a failed update from leaving a half-written app.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Codable, Equatable {
        var version: String
        var build: Int
        var url: String
        var notes: String?
        var minimumSystemVersion: String?
        var publishedAt: Date?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(Release)
        case downloading(Double)
        case downloaded(URL)
        case failed(String)

        /// The one-line status the settings pane shows.
        var summary: String {
            switch self {
            case .idle:               return "Not checked yet"
            case .checking:           return "Checking…"
            case .upToDate(let when): return "Up to date · \(when.formatted(date: .abbreviated, time: .shortened))"
            case .available(let r):   return "Version \(r.version) is available"
            case .downloading(let p): return "Downloading… \(Int(p * 100))%"
            case .downloaded:         return "Ready to install"
            case .failed(let why):    return why
            }
        }
    }

    @Published private(set) var state: State = .idle

    /// Where the appcast lives. Overridable so a build can point at a staging
    /// feed without a recompile.
    @Published var feedURL: String {
        didSet { UserDefaults.standard.set(feedURL, forKey: Self.feedKey) }
    }

    @Published var checksAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(checksAutomatically, forKey: Self.autoKey)
            scheduleAutomaticChecks()
        }
    }

    private static let feedKey = "dockly.update.feed"
    private static let autoKey = "dockly.update.auto"
    private static let defaultFeed = "https://dockly.app/appcast.json"

    private var timer: Timer?
    private var task: URLSessionTask?

    private init() {
        feedURL = UserDefaults.standard.string(forKey: Self.feedKey) ?? Self.defaultFeed
        checksAutomatically = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
    }

    // MARK: Version of the running build

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
    }

    // MARK: Checking

    func start() {
        scheduleAutomaticChecks()
        guard checksAutomatically else { return }
        // Not on the very first tick — launch is busy enough already.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.check(userInitiated: false)
        }
    }

    private func scheduleAutomaticChecks() {
        timer?.invalidate()
        timer = nil
        guard checksAutomatically else { return }
        timer = everySecond(6 * 60 * 60) { [weak self] in self?.check(userInitiated: false) }
    }

    func check(userInitiated: Bool) {
        guard let url = URL(string: feedURL) else {
            state = .failed("That update feed address is not valid")
            return
        }
        if case .checking = state { return }
        if case .downloading = state { return }
        state = .checking

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    self.state = userInitiated
                        ? .failed("Could not reach the update feed — \(error.localizedDescription)")
                        : .idle
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    self.state = userInitiated
                        ? .failed("Update feed returned \(http.statusCode)") : .idle
                    return
                }
                guard let data, let release = Self.decode(data) else {
                    self.state = userInitiated ? .failed("That feed is not a Dockly appcast") : .idle
                    return
                }
                if release.build > self.currentBuild {
                    self.state = .available(release)
                } else {
                    self.state = .upToDate(Date())
                }
            }
        }
        task?.resume()
    }

    private static func decode(_ data: Data) -> Release? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let one = try? decoder.decode(Release.self, from: data) { return one }
        // A feed may also be a list; newest build wins.
        if let many = try? decoder.decode([Release].self, from: data) {
            return many.max { $0.build < $1.build }
        }
        return nil
    }

    // MARK: Downloading

    func download(_ release: Release) {
        guard let url = URL(string: release.url) else {
            state = .failed("That release has no valid download")
            return
        }
        state = .downloading(0)

        let destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Dockly-\(release.version).\(url.pathExtension)")
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("Dockly-\(release.version).\(url.pathExtension)")

        task = URLSession.shared.downloadTask(with: url) { [weak self] temp, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let temp, error == nil else {
                    self.state = .failed(error?.localizedDescription ?? "Download failed")
                    return
                }
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.moveItem(at: temp, to: destination)
                    self.state = .downloaded(destination)
                } catch {
                    self.state = .failed("Could not save the download — \(error.localizedDescription)")
                }
            }
        }
        task?.resume()
    }

    func revealDownload(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }
}
