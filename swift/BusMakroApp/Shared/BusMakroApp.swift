import SwiftUI

@main
struct BusMakroApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate  // home screen quick actions
    #endif

    var body: some Scene {
        WindowGroup { ContentView().dynamicTypeSize(...DynamicTypeSize.xxxLarge) }  // follows Text Size, up to where the layout still holds
    }
}
