import Foundation

/// Localization uses the English UI text as the key, so SwiftUI's
/// `LocalizedStringKey` literals localize on their own and this helper only
/// covers the non-literal call sites (enums, formats, AppKit strings).
/// Translations live in `Resources/<lang>.lproj/Localizable.strings`, copied into
/// the bundle by `scripts/build-app.sh`; without the bundle the key itself — the
/// English text — is what shows.
enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
