import Foundation

/// Map basemap configuration. The MapTiler API key is injected at build time from the
/// (gitignored) `Config/maptiler.local.xcconfig` into `Info.plist`, so no key is committed to
/// the repo. With no key set the basemap tiles simply don't load — see README for setup.
enum MapConfig {
    static var maptilerKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MapTilerAPIKey") as? String) ?? ""
    }
}
