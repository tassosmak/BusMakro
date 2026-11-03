import BusMakroKit
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
            Image("Logo").resizable().frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .appearing(0)
            Text("Welcome to BusMakro").font(.scaled(28, .bold)).multilineTextAlignment(.center)
                .padding(.top, 18).appearing(1)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: f.0).font(.scaled(26)).foregroundStyle(.tint).frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.1).font(.scaled(15, .semibold))
                            Text(f.2).font(.scaled(14)).foregroundStyle(.secondary)
                        }
                    }
                    .appearing(3 + i)
                }
            }
            .padding(.horizontal, 32).padding(.top, 30)
            Spacer(minLength: 24)
            Button(action: onContinue) {
                Text("Continue").font(.scaled(17, .semibold)).frame(maxWidth: .infinity).frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
            .padding(.horizontal, 32).appearing(9)
            Button(notificationTitle) { notificationsTapped() }
                .font(.scaled(13)).padding(.top, 12).padding(.bottom, 24)
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

/// First launch: the welcome, then whether to save places at all; only on yes, one question each for
/// Home and Work (both skippable, asked once; they can be set later in Settings → Trips).
struct Onboarding: View {
    @Bindable var model: Model
    var onDone: () -> Void
    @State private var step = 0  // 0 welcome, 1 save places?, then one per saved place

    var body: some View {
        if step == 0 {
            WelcomeView { withAnimation { step = 1 } }
        } else if step == 1 {
            SavePlacesQuestion { yes in if yes { withAnimation { step = 2 } } else { onDone() } }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            let k = SavedPlace.allCases[step - 2]
            PlaceQuestion(model: model, place: k) { p in
                if let p { model[place: k] = p }
                if step - 1 < SavedPlace.allCases.count { withAnimation { step += 1 } } else { onDone() }
            }
            .id(k)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// "Save your places?": Yes goes on to Home and Work, Not Now finishes.
struct SavePlacesQuestion: View {
    var onAnswer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: SavedPlace.home.icon)
                    Image(systemName: SavedPlace.work.icon)
                }
                .font(.scaled(34, .semibold)).foregroundStyle(.tint)
                Text("Save your places?").font(.scaled(28, .bold)).multilineTextAlignment(.center)
                Text("Add Home and Work, and Take Me Home plans the trip there in one tap, from wherever you are. You can add them later in Settings.")
                    .font(.scaled(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            Button { onAnswer(true) } label: {
                Text("Add Home and Work").font(.scaled(17, .semibold)).frame(maxWidth: .infinity).frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
            .padding(.horizontal, 32)
            Button("Not Now") { onAnswer(false) }
                .font(.scaled(15)).padding(.top, 14).padding(.bottom, 24)
        }
        .frame(maxWidth: 520)
    }
}

/// "Where is Home?": search for the place, or Skip.
struct PlaceQuestion: View {
    @Bindable var model: Model
    let place: SavedPlace
    var onAnswer: (TripPlanner.Place?) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: place.icon).font(.scaled(34, .semibold)).foregroundStyle(.tint)
                    Text(place.question).font(.scaled(22, .bold))
                    Text(place == .home ? "Then Take Me Home plans the trip there in one tap, from wherever you are."
                                        : "Then Take Me to Work plans the trip there in one tap, from wherever you are.")
                        .font(.scaled(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32).padding(.top, 24)
                PlaceSearch(model: model, allowHere: false) { choice in
                    if case .place(let p) = choice { onAnswer(p) }
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Skip") { onAnswer(nil) } } }
        }
    }
}
