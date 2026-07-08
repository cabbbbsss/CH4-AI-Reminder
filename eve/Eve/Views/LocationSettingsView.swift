import SwiftUI

// MARK: - Location access settings (Sketch artboard BE688930)

struct LocationSettingsView: View {
    enum Access: String, CaseIterable {
        case never = "Never"
        case ask = "Ask Next Time or When I Share"
        case whileUsing = "While Using the App"
    }

    @State private var selection: Access = .never

    var body: some View {
        SettingsScaffold(title: "Location") {
            VStack(alignment: .leading, spacing: 16) {
                Text("ALLOW LOCATION ACCESS")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "#94A8BC"))
                    .padding(.horizontal, 24)

                SettingsCard {
                    ForEach(Array(Access.allCases.enumerated()), id: \.element) { index, option in
                        SettingsChoiceRow(
                            label: option.rawValue,
                            isSelected: selection == option
                        ) {
                            selection = option
                        }
                        if index < Access.allCases.count - 1 {
                            SettingsDivider()
                        }
                    }
                }

                Text("EVE keeps your location data on your device. It is used only to determine when to send reminders based on your current location, ensuring your routine stays private while providing timely notifications.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#94A8BC"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }
            .padding(.top, 20)
        }
    }
}

#Preview {
    NavigationStack {
        LocationSettingsView()
    }
}
