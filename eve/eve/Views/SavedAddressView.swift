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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
              stops: [
                .init(color: Color(.bgPrimary), location: 0.75),
                .init(color: Color(.bgSecondary), location: 1.0)
              ],
              startPoint: .bottom,
              endPoint: .top
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsNavBar(title: "Saved Address") { dismiss() }

                // A native List is required here (not ScrollView/VStack) so `.swipeActions`
                // gives the real Apple swipe-to-delete/edit gesture: half-swipe reveals
                // Edit + Delete, full swipe triggers Delete immediately.
                List {
                    ForEach($addresses) { $item in
                        AddressCard(
                            item: item,
                            onEdit: { showToast("Address updated successfully") },
                            onDelete: { delete(item) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                showToast("Address updated successfully")
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }

                    ZStack {
                        NavigationLink(destination: AddNewAddressView()) { EmptyView() }
                            .opacity(0)
                        Label("Add New Address", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(.textSecondary))
                            .frame(width: 200, height: 40)
                            .background(Color.accentColor)
                            .cornerRadius(20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSpacing(16)
                .contentMargins(.top, 20, for: .scrollContent)
            }
        }
        .navigationBarHidden(true)
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
                    .foregroundColor(Color(.textPrimary))
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
                        .foregroundColor(Color(.textQuarternary))
                        .frame(width: 32, height: 32)
                }
            }

            Text(item.address)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(.textQuarternary))
                .fixedSize(horizontal: false, vertical: true)

            if item.isPrimary {
                Text("Primary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.bgTertiary).opacity(0.6))
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.bgSecondary))
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
}

struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.accentColor)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Color(.textPrimary))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(.bgTertiary))
        .cornerRadius(16)
    }
}

#Preview {
    NavigationStack {
        SavedAddressView()
    }
}
