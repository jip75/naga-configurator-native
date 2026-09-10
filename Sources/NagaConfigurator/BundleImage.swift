import SwiftUI
import AppKit

/// Loose copied PNGs under Resources/ aren't in an .xcassets catalog, so Image(_:) can't find
/// them by name — load explicitly from Bundle.module instead.
extension Image {
    init(bundled name: String) {
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
           let nsImage = NSImage(contentsOf: url) {
            self.init(nsImage: nsImage)
        } else {
            self.init(systemName: "questionmark.square.dashed")
        }
    }
}
