import SwiftUI
import CoreText

@main
struct HarvardDiningApp: App {
    init() { Self.registerBundledFonts() }

    var body: some Scene {
        WindowGroup { RootView() }
    }

    /// Registers Crimson Text at launch. Done in code rather than via an
    /// Info.plist UIAppFonts array, because this target generates its
    /// Info.plist from build settings, which handle scalars but not arrays.
    private static func registerBundledFonts() {
        for name in ["CrimsonText-SemiBold", "CrimsonText-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
