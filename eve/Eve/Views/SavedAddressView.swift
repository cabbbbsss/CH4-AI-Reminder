import SwiftUI

// MARK: - Saved Address list (Sketch artboards C00BABD8 / B18D0FF7 / 2D37B19D)

struct SavedAddress: Identifiable {
    let id = UUID()
    var name: String
    var address: String
    var isPrimary: Bool
}

struct SavedAddressView: View {
    @State private var addresses: [SavedAddress] = [
        SavedAddress(
            name: "Home",
            address: "Address Kuta Tuban, Jalan Address Address, Tuban, Address, Address Kuta, Kab. Badung, Bali 12345",
            isPrimary: true
        ),
        SavedAddress(
            name: "Office",
            address: "Address Kuta Tuban, Jalan Address Address, Tuban, Address, Address Kuta, Kab. Badung, Bali 12345",
            isPrimary: false
        )
    ]
    @State private var toast: String?

    var body: some View {
        SettingsScaffold(title: "Saved Address") {
            VStack(spacing: 16) {
                ForEach($addresses) { $item in
                    AddressCard(
                        item: item,
                        onEdit: { showToast("Address updated successfully") },
                        onDelete: { delete(item) }
                    )
                }

                NavigationLink {
                    AddNewAddressView()
                } label: {
                    Label("Add New Address", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#E0ECF7"))
                        .frame(width: 200, height: 40)
                        .background(Color(hex: "#368BC8"))
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.top, 20)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                SuccessToast(message: toast)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func delete(_ item: SavedAddress) {
        addresses.removeAll { $0.id == item.id }
        showToast("Address deleted")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toast = nil }
        }
    }
}

struct AddressCard: View {
    let item: SavedAddress
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "#1E3659"))
                Spacer()
                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "#94A8BC"))
                        .frame(width: 32, height: 32)
                }
            }

            Text(item.address)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#94A8BC"))
                .fixedSize(horizontal: false, vertical: true)

            if item.isPrimary {
                Text("Primary")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#4F83AB"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#C4D7EA").opacity(0.6))
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#E8F3FF"))
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
}

struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: "#0091FF"))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#1D3557"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(hex: "#C4D7EA"))
        .cornerRadius(16)
    }
}

#Preview {
    NavigationStack {
        SavedAddressView()
    }
}
