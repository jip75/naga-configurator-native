import SwiftUI
import AppKit

/// SwiftPM's generated Bundle.module only ever looks in Bundle.main.bundleURL (the .app's own
/// top level), which codesign refuses to seal anything else in — putting the resource bundle
/// there breaks Developer ID signing ("unsealed contents present in the bundle root"). Contents/
/// Resources is the one location both codesign and a packaged .app agree on, so check there
/// first (release.sh puts the bundle there) and only fall back to Bundle.module for `swift run`/
/// unpackaged dev builds, where there's no Contents/Resources to find.
private extension Bundle {
    static let nagaResources: Bundle = {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("NagaConfigurator_NagaConfigurator.bundle")
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return Bundle.module
    }()
}

/// Loose copied PNGs under Resources/ aren't in an .xcassets catalog, so Image(_:) can't find
/// them by name — load explicitly instead.
extension Image {
    init(bundled name: String) {
        if let url = Bundle.nagaResources.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
           let nsImage = NSImage(contentsOf: url) {
            self.init(nsImage: nsImage)
        } else {
            self.init(systemName: "questionmark.square.dashed")
        }
    }
}
