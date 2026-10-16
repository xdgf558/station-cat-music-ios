import Foundation

enum LegalLinks {
    enum Page: String { case privacy, terms }

    static func url(_ page: Page, locale: String) -> URL {
        let language = ["en": "en", "zh-Hans": "zh-hans", "zh-Hant": "zh-hant", "ja": "ja"][locale] ?? "en"
        return URL(string: "\(ProductionActivationProfile.origin)/\(language)/\(page.rawValue)/")!
    }
}
