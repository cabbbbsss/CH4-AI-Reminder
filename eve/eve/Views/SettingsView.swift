import SwiftUI
import SwiftData
import UIKit

// MARK: - Main Settings hub (Sketch artboard 5CF849E7)

/// App-wide appearance preference. `system` follows the device until the user
/// flips the Dark Mode toggle, which commits an explicit `light`/`dark` choice.
enum AppThemePreference: String {
    case system, light, dark
}

struct SettingsView: View {
    @Bindable var permissionManager = PermissionManager.shared

    @Environment(\.modelContext) private var modelContext
    @State private var profile: UserProfile?

    /// Edits flow straight through to the persisted UserProfile and save,
    /// so the name survives relaunches and is visible to Home + notifications.
    private var nameBinding: Binding<String> {
        Binding(
            get: { profile?.name ?? "" },
            set: { newValue in
                let target = profile ?? UserProfile.current(in: modelContext)
                profile = target
                target.name = newValue
                try? modelContext.save()
            }
        )
    }

    // TEMPORARY — state for the notification preview demo. Delete with the section below.
    @State private var notificationService = NotificationService()
    @State private var demoRunning = false

    @AppStorage("appThemePreference") private var themeRaw = AppThemePreference.system.rawValue
    @Environment(\.colorScheme) private var systemScheme

    private var isDarkMode: Binding<Bool> {
        Binding(
            get: {
                switch AppThemePreference(rawValue: themeRaw) ?? .system {
                case .system: return systemScheme == .dark
                case .light:  return false
                case .dark:   return true
                }
            },
            set: { themeRaw = $0 ? AppThemePreference.dark.rawValue : AppThemePreference.light.rawValue }
        )
    }

    var body: some View {
        SettingsScaffold(title: "Settings") {
            VStack(spacing: 28) {
                
                // Profile
                SettingsSection(header: "Profile") {
                    SettingsCard {
                        SettingsValueRow(label: "Name", value: nameBinding, trailingIcon: "pencil", isEditable: true)
                    }
                }
                
                // Allow EVE to Access
                SettingsSection(header: "Allow EVE to Access") {
                    SettingsCard {
                        SettingsNavRow(icon: "calendar", label: "Calendar") {
                            PermissionStatusSettingsView(
                                title: "Calendar",
                                statusKeyPath: \.isCalendarGranted,
                                description: "EVE reads and updates your calendar events to build your routine and schedule reminders. Calendar access is managed by iOS — use the Settings app to change it."
                            )
                        }
                        SettingsDivider()
                        SettingsNavRow(icon: "checklist", label: "Reminder") {
                            PermissionStatusSettingsView(
                                title: "Reminder",
                                statusKeyPath: \.isReminderGranted,
                                description: "EVE reads and creates reminders so it can nudge you at the right time. Reminder access is managed by iOS — use the Settings app to change it."
                            )
                        }
                        SettingsDivider()
                        SettingsNavRow(icon: "location.fill", label: "Location") {
                            PermissionStatusSettingsView(
                                title: "Location",
                                statusKeyPath: \.isLocationGranted,
                                description: "EVE uses your location to send timely, location-based reminders. Location access is managed by iOS — use the Settings app to change it."
                            )
                        }
                        SettingsDivider()
                        SettingsNavRow(icon: "bell.badge.fill", label: "Notification") {
                            NotificationSettingsView()
                        }
                    }
                }

                // Display & Appearance
                SettingsSection(header: "Display & Appearance") {
                    SettingsCard {
                        SettingsToggleRow(label: "Dark Mode", isOn: isDarkMode)
                    }
                }

//                // General App
//                SettingsSection(header: "General App") {
//                    SettingsCard {
//                        SettingsRow(label: "Language")
//                        SettingsDivider()
//                        SettingsRow(label: "Legal & Privacy")
//                    }
//                }

                // TEMPORARY — Notification preview demo. Delete this whole section when done.
                SettingsSection(header: "Notification Preview (Demo)") {
                    SettingsCard {
                        Button {
                            demoRunning = true
                            Task { await notificationService.startDemoNotifications() }
                        } label: {
                            SettingsRow(icon: "bell.badge.fill", label: "Start demo (fires every 10s)", showChevron: false)
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        Button {
                            demoRunning = false
                            notificationService.cancelDemoNotifications()
                        } label: {
                            SettingsRow(icon: "bell.slash.fill", label: "Stop demo", showChevron: false)
                        }
                        .buttonStyle(.plain)
                    }

                    if demoRunning {
                        Text("Sending sample event, reminder, and location notifications every 10 seconds for ~5 minutes. Lock your phone or leave the app to see them on the lock screen.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(.textTertiary))
                            .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .task {
            profile = UserProfile.current(in: modelContext)
        }
    }
}

// MARK: - Shared settings chrome (reused by every settings screen)

/// Background + custom nav bar + scrolling content, matching the EVE design language.
struct SettingsScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    /// Restores the swipe-to-go-back gesture that the hidden nav bar below
    /// suppresses, so a right-swipe pops the screen (Settings → Home, and each
    /// settings sub-screen → the previous one). Every settings screen builds on
    /// this scaffold, so wiring it here enables swipe-back across all of them.
    @State private var popEnabler = PopGestureEnabler()

    var body: some View {
        ZStack {
            Color(.bgPrimary).ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsNavBar(title: title) { dismiss() }

                ScrollView(showsIndicators: false) {
                    content
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            popEnabler.enable()
            // The nav hierarchy may not be fully wired on the first tick of a
            // push; re-apply next runloop so we don't miss the recognizer.
            DispatchQueue.main.async { popEnabler.enable() }
        }
        .onDisappear {
            popEnabler.restore()
        }
    }
}

struct SettingsNavBar: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(.textPrimary))

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(.textPrimary))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 64)
    }
}

struct SettingsSection<Content: View>: View {
    let header: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(header)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(.textPrimary))
                .padding(.horizontal, 24)

            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(.bgSecondary))
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(.textPrimary).opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 18)
    }
}

/// A plain informational row (label + chevron).
struct SettingsRow: View {
    var icon: String? = nil
    var label: String
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(Color(.textPrimary))
                    .frame(width: 26)
            }
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(Color(.textPrimary))
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.textTertiary))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}

/// A row that displays a value (and optional trailing glyph) instead of a chevron.
/// When `isEditable` is true, tapping the trailing icon turns the value into an editable text field.
struct SettingsValueRow: View {
    var label: String
    @Binding var value: String
    var trailingIcon: String? = nil
    var isEditable: Bool = false

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(Color(.textPrimary))
            Spacer()
            if isEditing {
                TextField("", text: $value)
                    .font(.system(size: 17))
                    .foregroundColor(Color(.textPrimary))
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { isEditing = false }
            } else {
                Text(value)
                    .font(.system(size: 17))
                    .foregroundColor(Color(.textPrimary).opacity(0.7))
            }
            if let trailingIcon, isEditable {
                Button {
                    isEditing.toggle()
                    isFocused = isEditing
                } label: {
                    Image(systemName: isEditing ? "checkmark" : trailingIcon)
                        .font(.system(size: 15))
                        .foregroundColor(Color(.textPrimary).opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}

/// A tappable row that pushes a destination.
struct SettingsNavRow<Destination: View>: View {
    var icon: String? = nil
    var label: String
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }
}

/// Custom pill switch matching the design's blue toggle.
struct EVEToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(Color.accentColor)
    }
}

/// A row with a trailing blue switch.
struct SettingsToggleRow: View {
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(Color(.textPrimary))
            Spacer()
            EVEToggle(isOn: $isOn)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }
}

/// A selectable row with a leading checkmark when chosen.
struct SettingsChoiceRow: View {
    var label: String
    var isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(Color(.textPrimary))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.accentColor)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Swipe-back enabler

/// Re-enables the interactive swipe-to-go-back gesture while a settings screen
/// owns the display. `SettingsScaffold` hides the navigation bar
/// (`.navigationBarHidden(true)`), and iOS blocks swipe-back whenever the bar
/// is hidden — so without this the only way back is the chevron button.
///
/// This is the mirror image of `PopGestureGuard` in CalendarView: it enables
/// the recognizers and installs a delegate that *permits* the pop, rather than
/// disabling them and refusing it. iOS 26 splits swipe-back into two
/// recognizers — the edge pan (`interactivePopGestureRecognizer`) and the
/// full-content pan (`interactiveContentPopGestureRecognizer`) — so both are
/// restored, with each recognizer's original state captured for `restore()`.
private final class PopGestureEnabler: NSObject, UIGestureRecognizerDelegate {

    /// One recognizer's original state, so `restore()` can put it back exactly.
    private final class Capture {
        weak var gesture: UIGestureRecognizer?
        let wasEnabled: Bool
        weak var previousDelegate: UIGestureRecognizerDelegate?
        init(_ gesture: UIGestureRecognizer) {
            self.gesture = gesture
            self.wasEnabled = gesture.isEnabled
            self.previousDelegate = gesture.delegate
        }
    }

    private var captures: [Capture] = []
    private var capturedIDs = Set<ObjectIdentifier>()

    /// Permit the pop only when there's a screen to go back to, so a swipe on
    /// the navigation root can't try to pop nothing.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        for nav in Self.navigationControllers() {
            if nav.interactivePopGestureRecognizer === gestureRecognizer
                || nav.interactiveContentPopGestureRecognizer === gestureRecognizer {
                return nav.viewControllers.count > 1
            }
        }
        return false
    }

    /// Coexist with the scaffold's vertical ScrollView pan so scrolling still works.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func enable() {
        for gesture in Self.popRecognizers() {
            // Capture each recognizer's original state exactly once, before we
            // touch it, so a repeated enable() never records our own values.
            if capturedIDs.insert(ObjectIdentifier(gesture)).inserted {
                captures.append(Capture(gesture))
            }
            gesture.isEnabled = true
            gesture.delegate = self
        }
    }

    func restore() {
        for capture in captures {
            guard let gesture = capture.gesture else { continue }
            // Only revert if we're still the active delegate. When a settings
            // sub-screen is pushed, its scaffold takes over the same recognizer
            // before this parent scaffold disappears; reverting then would
            // clobber the child's setup and kill swipe-back on the child.
            guard gesture.delegate === self else { continue }
            gesture.isEnabled = capture.wasEnabled
            gesture.delegate = capture.previousDelegate
        }
        captures.removeAll()
        capturedIDs.removeAll()
    }

    /// Every navigation controller in the app's window hierarchy, de-duplicated.
    /// Sweeps all scenes rather than a single `navigationController`, since
    /// SwiftUI may host our content outside the nav controller's subtree.
    private static func navigationControllers() -> [UINavigationController] {
        var result: [UINavigationController] = []
        var seen = Set<ObjectIdentifier>()

        func walk(_ viewController: UIViewController?) {
            guard let viewController else { return }
            if let nav = viewController as? UINavigationController,
               seen.insert(ObjectIdentifier(nav)).inserted {
                result.append(nav)
            }
            viewController.children.forEach(walk)
            walk(viewController.presentedViewController)
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                walk(window.rootViewController)
            }
        }
        return result
    }

    private static func popRecognizers() -> [UIGestureRecognizer] {
        navigationControllers().flatMap { nav in
            [nav.interactivePopGestureRecognizer, nav.interactiveContentPopGestureRecognizer]
                .compactMap { $0 }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
