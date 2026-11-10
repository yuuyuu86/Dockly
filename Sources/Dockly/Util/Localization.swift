import Foundation

/// Looks a string up in the app bundle's `.lproj` tables.
///
/// Keys are the English text, so an untranslated string still reads correctly
/// and a missing table is harmless — which keeps the call sites readable.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// The same, for strings that interpolate a value.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .main, comment: ""), arguments: arguments)
}
