import SwiftUI
import UserNotifications

/// First-launch welcome, Apple style (as the Mac app's): the icon, a large title, the main features
/// with accent-coloured symbols, one Continue button; everything eases in, top to bottom.
struct WelcomeView: View {
    var onContinue: () -> Void
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL

    private let features: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("bus.fill", "Live buses", "Official OASA arrival times, and every bus moving on the map."),
        ("mappin.and.ellipse", "Stops around you", "Opens on the stops nearest to you. Move the map to explore any area."),
        ("star.fill", "Favourite stops", "Star a stop to keep it one tap away."),
        ("magnifyingglass", "Search everything", "Find any line or stop, in Greek or Latin letters."),
        ("bell.badge", "Bus alerts", "Get a notification when your bus is a few stops away."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: "bus.fill")
                .font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(LinearGradient(colors: [.blue, Color(red: 0.05, green: 0.35, blue: 0.9)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 22))
                .appearing(0)
            Text("Welcome to BusMakro").font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center)
                .padding(.top, 18).appearing(1)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: f.0).font(.system(size: 26)).foregroundStyle(.tint).frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.1).font(.system(size: 15, weight: .semibold))
                            Text(f.2).font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                    }
                    .appearing(3 + i)
                }
            }
            .padding(.horizontal, 32).padding(.top, 30)
            Spacer(minLength: 24)
            Button(action: onContinue) {
                Text("Continue").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
            .padding(.horizontal, 32).appearing(9)
            Button(notificationTitle) { notificationsTapped() }
                .font(.system(size: 13)).padding(.top, 12).padding(.bottom, 24)
                .disabled(notifications == .authorized)
                .appearing(10)
        }
        .frame(maxWidth: 520)
        .task { await refreshNotifications() }
    }

    private var notificationTitle: LocalizedStringKey {
        switch notifications {
        case .authorized, .provisional, .ephemeral: return "Notifications are on ✓"
        case .denied: return "Turn On Notifications in Settings…"
        default: return "Turn On Notifications"
        }
    }

    private func notificationsTapped() {
        if notifications == .notDetermined {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                Task { await refreshNotifications() }
            }
        } else {
            #if os(iOS)
            if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
            #endif
        }
    }

    @MainActor private func refreshNotifications() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
