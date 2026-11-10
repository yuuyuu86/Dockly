import Foundation
import Combine
import Security

// MARK: - Keychain (API keys never touch the JSON library)

enum Keychain {
    private static let service = "app.dockly.Dockly"

    static func set(_ value: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Revenue

struct RevenueSnapshot {
    var label: String = "Revenue"
    var amount: Double = 0
    var currency: String = "USD"
    var secondary: String = "MTD"
    var trend: [Double] = []
    var updated: Date = .distantPast
    var error: String?

    var formatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = amount >= 1000 ? 1 : 2
        if amount >= 1000 {
            let short = amount / 1000
            let symbol = f.currencySymbol ?? "$"
            return String(format: "%@%.1fK", symbol, short)
        }
        return f.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

enum RevenueProvider: String { case stripe, paddle }

/// Pulls month-to-date revenue from Stripe or Paddle. Keys live in the
/// Keychain; only the account name is stored in the library.
final class RevenueSource: ObservableObject {
    static let stripe = RevenueSource(provider: .stripe)
    static let paddle = RevenueSource(provider: .paddle)

    static func source(for kind: WidgetKind) -> RevenueSource {
        kind == .paddle ? .paddle : .stripe
    }

    let provider: RevenueProvider
    @Published private(set) var snapshot = RevenueSnapshot()
    @Published private(set) var isLoading = false

    private var timer: Timer?

    var keychainAccount: String { "\(provider.rawValue).apiKey" }

    var apiKey: String? {
        get { Keychain.get(keychainAccount) }
        set { Keychain.set(newValue, for: keychainAccount); refresh(force: true) }
    }

    private init(provider: RevenueProvider) {
        self.provider = provider
        snapshot.label = provider == .stripe ? "Stripe" : "Paddle"
        timer = everySecond(600) { [weak self] in self?.refresh() }
    }

    func refresh(force: Bool = false) {
        guard !isLoading else { return }
        guard let key = apiKey, !key.isEmpty else {
            snapshot.error = "Add an API key"
            return
        }
        if !force, Date().timeIntervalSince(snapshot.updated) < 120 { return }
        isLoading = true
        switch provider {
        case .stripe: fetchStripe(key)
        case .paddle: fetchPaddle(key)
        }
    }

    // MARK: Stripe

    private func fetchStripe(_ key: String) {
        let start = Int(startOfMonth().timeIntervalSince1970)
        var comps = URLComponents(string: "https://api.stripe.com/v1/charges")!
        comps.queryItems = [
            .init(name: "limit", value: "100"),
            .init(name: "created[gte]", value: String(start)),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async { self.isLoading = false }
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.fail(error?.localizedDescription ?? "Stripe unreachable"); return
            }
            if let err = root["error"] as? [String: Any] {
                self.fail((err["message"] as? String) ?? "Stripe error"); return
            }
            let charges = (root["data"] as? [[String: Any]]) ?? []
            var total: Double = 0
            var currency = "USD"
            var daily: [Int: Double] = [:]
            let cal = Calendar.current
            for c in charges {
                guard (c["paid"] as? Bool) == true, (c["refunded"] as? Bool) != true else { continue }
                let minor = (c["amount"] as? Double) ?? 0
                let value = minor / 100
                total += value
                if let cur = c["currency"] as? String { currency = cur.uppercased() }
                if let created = c["created"] as? Double {
                    let day = cal.component(.day, from: Date(timeIntervalSince1970: created))
                    daily[day, default: 0] += value
                }
            }
            let trend = (1...max(1, cal.component(.day, from: Date()))).map { daily[$0] ?? 0 }
            self.succeed(total: total, currency: currency, secondary: "MTD", trend: trend)
        }.resume()
    }

    // MARK: Paddle

    private func fetchPaddle(_ key: String) {
        var comps = URLComponents(string: "https://api.paddle.com/transactions")!
        let iso = ISO8601DateFormatter()
        comps.queryItems = [
            .init(name: "status", value: "completed"),
            .init(name: "per_page", value: "100"),
            .init(name: "billed_at", value: "GTE:\(iso.string(from: startOfMonth()))"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async { self.isLoading = false }
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { self.fail(error?.localizedDescription ?? "Paddle unreachable"); return }

            if let err = root["error"] as? [String: Any] {
                self.fail((err["detail"] as? String) ?? "Paddle error"); return
            }
            let txs = (root["data"] as? [[String: Any]]) ?? []
            var total: Double = 0
            var currency = "USD"
            var daily: [Int: Double] = [:]
            let cal = Calendar.current
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for t in txs {
                guard let details = t["details"] as? [String: Any],
                      let totals = details["totals"] as? [String: Any] else { continue }
                let minor = Double((totals["grand_total"] as? String) ?? "0") ?? 0
                let value = minor / 100
                total += value
                if let cur = totals["currency_code"] as? String { currency = cur }
                if let stamp = t["billed_at"] as? String,
                   let date = iso.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) {
                    daily[cal.component(.day, from: date), default: 0] += value
                }
            }
            let trend = (1...max(1, cal.component(.day, from: Date()))).map { daily[$0] ?? 0 }
            self.succeed(total: total, currency: currency, secondary: "MTD", trend: trend)
        }.resume()
    }

    // MARK: Helpers

    private func startOfMonth() -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async {
            self.snapshot.error = message
            self.snapshot.updated = Date()
        }
    }

    private func succeed(total: Double, currency: String, secondary: String, trend: [Double]) {
        DispatchQueue.main.async {
            var s = self.snapshot
            s.amount = total
            s.currency = currency
            s.secondary = secondary
            s.trend = trend
            s.error = nil
            s.updated = Date()
            self.snapshot = s
        }
    }
}
