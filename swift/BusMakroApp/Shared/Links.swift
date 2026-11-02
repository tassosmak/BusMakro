import BusMakroKit
import Foundation
import Observation
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Ways into the app from outside it: home screen quick actions, Siri and Shortcuts, Spotlight,
/// the Live Activity, and busmakro:// links. Each becomes an `AppLink`, which ContentView hands
/// to the model once it is ready.
enum AppLink: Equatable {
    case stop(String), line(String), station(String), search, favourites, nearby, plan, home

    /// busmakro://stop/400022 · busmakro://line/040 · busmakro://search · busmakro://favourites
    init?(url: URL) {
        guard url.scheme == "busmakro", let host = url.host() else { return nil }
        let arg = url.pathComponents.dropFirst().first ?? ""
        switch host {
        case "stop" where !arg.isEmpty: self = .stop(arg)
        case "line" where !arg.isEmpty: self = .line(arg)
        case "station" where !arg.isEmpty: self = .station(arg)
        case "search": self = .search
        case "favourites": self = .favourites
        case "nearby": self = .nearby
        case "plan": self = .plan
        case "home": self = .home
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case .stop(let id): URL(string: "busmakro://stop/\(id)")!
        case .line(let id): URL(string: "busmakro://line/\(id)")!
        case .station(let id): URL(string: "busmakro://station/\(id)")!
        case .search: URL(string: "busmakro://search")!
        case .favourites: URL(string: "busmakro://favourites")!
        case .nearby: URL(string: "busmakro://nearby")!
        case .plan: URL(string: "busmakro://plan")!
        case .home: URL(string: "busmakro://home")!
        }
    }
}

/// The link waiting to be opened (set by intents and quick actions, which can arrive before the
/// window exists).
@MainActor @Observable
final class Links {
    static let shared = Links()
    var pending: AppLink?
}

extension Model {
    /// Find a stop by its id in what we already know: favourites, recents, nearby, the stop index.
    func knownStop(_ id: String) -> Stop? {
        if let s = (favourites + recents + stops).first(where: { $0.id == id }) { return s }
        if let e = stopIndex?.stops[id] {
            return Stop(id: id, name: e.name, nameEnglish: "", street: "", latitude: e.lat, longitude: e.lon)
        }
        return nil
    }

    func follow(_ link: AppLink) async {
        switch link {
        case .stop(let id):
            // a link can arrive at launch, before the stop index has loaded: wait for it a little
            for _ in 0..<40 where knownStop(id) == nil { try? await Task.sleep(for: .milliseconds(250)) }
            if let s = knownStop(id) { searchActive = false; open(s) }
        case .line(let id):
            searchActive = false
            openLine(id, at: nil)
        case .station(let id):
            openStation(id)
        case .search:
            screen = .home
            searchActive = true
        case .favourites:
            screen = .home; homeTab = .favourites; searchActive = false
        case .nearby:
            screen = .home; homeTab = .nearby; searchActive = false
        case .plan:
            searchActive = false; showTrip = true
        case .home:
            takeMeHome()
        }
    }
}

#if os(iOS)
// MARK: Home screen quick actions (long-press the icon)

/// Two favourite stops, then Take Me Home and Search (four is the most iOS shows).
@MainActor
enum QuickActions {
    static func update(favourites: [Stop]) {
        var items = favourites.prefix(2).map { s in
            UIApplicationShortcutItem(type: "stop", localizedTitle: s.title, localizedSubtitle: String(localized: "Stop \(s.id)"),
                                      icon: UIApplicationShortcutIcon(systemImageName: "star.fill"),
                                      userInfo: ["id": s.id as NSString])
        }
        items.append(UIApplicationShortcutItem(type: "home", localizedTitle: String(localized: "Take Me Home"), localizedSubtitle: nil,
                                               icon: UIApplicationShortcutIcon(systemImageName: "house.fill"), userInfo: nil))
        items.append(UIApplicationShortcutItem(type: "search", localizedTitle: String(localized: "Search"), localizedSubtitle: nil,
                                               icon: UIApplicationShortcutIcon(type: .search), userInfo: nil))
        UIApplication.shared.shortcutItems = items
    }

    static func link(for item: UIApplicationShortcutItem) -> AppLink? {
        switch item.type {
        case "stop": (item.userInfo?["id"] as? String).map(AppLink.stop)
        case "search": .search
        case "home": .home
        default: nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Bus alerts also show while the app is open (without this, iOS drops them silently).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem, let link = QuickActions.link(for: item) {  // launched from a quick action
            MainActor.assumeIsolated { Links.shared.pending = link }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let link = QuickActions.link(for: shortcutItem)
        MainActor.assumeIsolated { Links.shared.pending = link }
        completionHandler(link != nil)
    }
}
#endif
