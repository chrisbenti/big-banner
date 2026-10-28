import Foundation

// cspell:ignore HTTPURL

/// Decides whether the installed build is behind origin/main on GitHub.
///
/// The latest sha is fetched at most once every 24 hours and cached on disk;
/// in between, the cached value is compared against the build's own hash.
/// Dirty builds (hash ends in `*`) never check and never show the badge.
enum UpdateCheck {
    private static let commitURL = URL(string: "https://api.github.com/repos/chrisbenti/big-banner/commits/main")!
    private static let interval: TimeInterval = 24 * 60 * 60

    private struct Cache: Codable {
        var sha: String?
        var checkedAt: Date
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("big-banner/update-check.json")
    }

    // BIG_BANNER_FORCE_UPDATE_CHECK=1 ignores the dirty-build skip and the
    // 24h cache, for testing from a working tree.
    private static let forced = ProcessInfo.processInfo.environment["BIG_BANNER_FORCE_UPDATE_CHECK"] == "1"

    /// False for dirty or unknown builds, which are never checked.
    private static var isCheckable: Bool {
        forced || (buildHash != "unknown" && !buildHash.hasSuffix("*"))
    }

    private static func readCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Cache.self, from: data)
    }

    private static func writeCache(_ cache: Cache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func isOutdated(latest: String?) -> Bool {
        guard let latest else { return false }
        return latest != buildHash.replacingOccurrences(of: "*", with: "")
    }

    /// Whether the cached answer says an update is available. Never touches the network.
    static func cachedUpdateAvailable() -> Bool {
        guard isCheckable else { return false }
        return isOutdated(latest: readCache()?.sha)
    }

    /// If the cache is older than 24h, asks GitHub for the latest sha in the
    /// background and calls `completion` on the main queue with whether an
    /// update is available. Does nothing when the cache is fresh or the build is dirty.
    static func refreshIfStale(completion: @escaping (Bool) -> Void) {
        guard isCheckable else { return }
        let cache = readCache()
        // A checkedAt in the future (clock change, bad file) counts as stale.
        let age = cache.map { Date().timeIntervalSince($0.checkedAt) }
        if !forced, let age, age >= 0, age < interval {
            log("UpdateCheck: cache is fresh, skipping fetch")
            return
        }
        // Record the attempt up front so banners dismissed before the fetch
        // finishes (or launched in a burst) don't each hit GitHub again.
        writeCache(Cache(sha: cache?.sha, checkedAt: Date()))

        var request = URLRequest(url: commitURL, timeoutInterval: 5)
        // Asks the API for just the commit sha as plain text.
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        // Ephemeral so URLSession doesn't drop its own Cache.db next to ours.
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            let body = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isSha = body?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && isSha
            log("UpdateCheck: fetched \(ok ? body! : "nothing") (error: \(String(describing: error)))")
            // A failed fetch keeps the previous sha and still waits another 24h.
            let sha = ok ? body : cache?.sha
            writeCache(Cache(sha: sha, checkedAt: Date()))
            let outdated = isOutdated(latest: sha)
            DispatchQueue.main.async { completion(outdated) }
        }.resume()
    }
}
