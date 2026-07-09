import SwiftUI

// MARK: - Add New Address form (Sketch artboards A3792CBC / C818F200 / C0479690 / 686646BD)

struct AddNewAddressView: View {
    enum AddressLabel: String, CaseIterable, Identifiable {
        case home = "Home"
        case office = "Office"
        case others = "Others"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: return "house"
            case .office: return "briefcase"
            case .others: return "mappin.and.ellipse"
            }
        }
    }

    private let suggestions = [
        "Park 23, Jl. Sarimande 67",
        "Park 23, Jl. Sarimande 67",
        "Park 23, Jl. Sarimande 67"
    ]

    @State private var searchText = ""
    @State private var selectedLabel: AddressLabel? = .office
    @State private var isPrimary = false

    var body: some View {
        SettingsScaffold(title: "Add New Address") {
            VStack(alignment: .leading, spacing: 20) {
                // Search
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search for an address")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(.textPrimary))

                    HStack(spacing: 10) {
                        TextField("Enter street, building or area", text: $searchText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(.textPrimary))
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(.textQuarternary))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color(.bgSecondary))
                    .cornerRadius(14)

                    if !searchText.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                Button {
                                    searchText = suggestion
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 13))
                                            .foregroundColor(Color(.textPrimary))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(Color(.textPrimary))
                                            Text("Kuta, Kab. Badung, Bali")
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(.textQuarternary))
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < suggestions.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(.bgSecondary))
                        .cornerRadius(14)
                    }
                }

                // Label as
                VStack(alignment: .leading, spacing: 14) {
                    Text("Label as")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(.textPrimary))

                    HStack(spacing: 12) {
                        ForEach(AddressLabel.allCases) { label in
                            LabelTile(
                                label: label,
                                isSelected: selectedLabel == label
                            ) {
                                selectedLabel = label
                            }
                        }
                    }
                }

                // Primary toggle
                HStack {
                    Text("Set as Primary Address")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.textQuarternary))
                    Spacer()
                    EVEToggle(isOn: $isPrimary)
                }

                Spacer(minLength: 40)

                // Save
                NavigationLink {
                    ConfirmLocationView()
                } label: {
                    Label("Save Address", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.textSecondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.accentColor)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .frame(minHeight: 720, alignment: .top)
        }
    }
}

struct LabelTile: View {
    let label: AddNewAddressView.AddressLabel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.accentColor : Color(.bgTertiary))
                    .frame(height: 60)
                    .overlay(
                        Image(systemName: label.icon)
                            .font(.system(size: 24))
                            .foregroundColor(isSelected ? .white : Color(.textPrimary))
                    )
                Text(label.rawValue)
                    .font(.system(size: 11))
                    .foregroundColor(Color(.textPrimary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        AddNewAddressView()
    }
}
