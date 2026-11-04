import SwiftUI
import TipKit

@main
struct BusMakroApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate  // home screen quick actions
    #endif

    init() {
        try? Tips.configure([.displayFrequency(.immediate)])
        RatingPrompt.noteUse()
        Diagnostics.shared.start()
    }

    var body: some Scene {
        WindowGroup { ContentView() }  // follows Text Size all the way, Accessibility sizes included (the map's buttons cap their own)
    }
}
