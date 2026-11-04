import SwiftUI

@main
struct BusMakroApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate  // home screen quick actions
    #endif

    var body: some Scene {
        WindowGroup { ContentView() }  // follows Text Size all the way, Accessibility sizes included (the map's buttons cap their own)
    }
}
