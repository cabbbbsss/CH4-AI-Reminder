import SwiftUI

struct Location: Identifiable {
    let id = UUID()
    var iconName: String
    var title: String
    var subtitle: String
    var address: String? = nil
    var recentlyEdited: Bool = false
    var reminders: [String]
    var extraCount: Int = 0
}

struct LocationView: View {
    @Environment(\.dismiss) var dismiss
    @State private var locations: [Location] = [
        Location(
            iconName: "house.fill",
            title: "Home",
            subtitle: "Eve has learned 5 reminders",
            address: "􀋒 Jl. Kediri...",
            reminders: ["Feed the dog", "Turn on rice cooker", "Call Mom"],
            extraCount: 2
        ),
        Location(
            iconName: "building.2.fill",
            title: "Office",
            subtitle: "Eve has learned 5 reminders",
            recentlyEdited: true,
            reminders: ["Feed the dog", "Turn on rice cooker", "Call Mom"],
            extraCount: 2
        ),
        Location(
            iconName: "cup.and.saucer.fill",
            title: "Max & Nine Cafe",
            subtitle: "Eve has learned 5 reminders",
            reminders: ["Feed the dog", "Turn on rice cooker", "Call Mom"],
            extraCount: 2
        ),
        Location(
            iconName: "fork.knife",
            title: "Resto Bintang 67",
            subtitle: "Eve has learned 5 reminders",
            reminders: ["Feed the dog", "Turn on rice cooker", "Call Mom"],
            extraCount: 2
        )
    ]
    @State private var toast: String?

    var body: some View {
        ZStack {
            Color(hex: "#4F83AB").ignoresSafeArea()

            GeometryReader { proxy in
                Ellipse()
                    .fill(Color(hex: "#E0ECF7"))
                    .frame(width: proxy.size.width * 2.5, height: proxy.size.height * 1.2)
                    .position(x: proxy.size.width / 2, y: -proxy.size.height * 0.1)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.backward.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .background(Circle().fill(Color.white))
                    }

                    Spacer()

                    Text("Locations")
                        .font(.system(size: 34, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "#1D3557"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)

                // A native List is required here (not ScrollView/VStack) so `.swipeActions`
                // gives the real Apple swipe-to-delete/edit gesture: half-swipe reveals
                // Edit + Delete, full swipe triggers Delete immediately.
                List {
                    ForEach($locations) { $location in
                        LocationCardView(
                            iconName: location.iconName,
                            title: location.title,
                            subtitle: location.subtitle,
                            address: location.address,
                            recentlyEdited: location.recentlyEdited,
                            reminders: location.reminders,
                            extraCount: location.extraCount
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(location)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                showToast("Location updated successfully")
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .listRowSpacing(20)
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .contentMargins(.bottom, 40, for: .scrollContent)
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

    private func delete(_ location: Location) {
        locations.removeAll { $0.id == location.id }
        showToast("Location deleted")
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toast = nil }
        }
    }
}

struct LocationCardView: View {
    var iconName: String
    var title: String
    var subtitle: String
    var address: String?
    var recentlyEdited: Bool = false
    var reminders: [String]
    var extraCount: Int = 0
    
    var body: some View {
        ZStack(alignment: .leading) {
            Color(hex: "#E8F3FF")
            
            // Large background icon
            VStack {
                Image(systemName: iconName)
                    .font(.system(size: 110))
                    .foregroundColor(Color(hex: "#C4D7EA"))
                    .offset(x: -30, y: 20)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(hex: "#1D3557"))
                    
                    if let address = address {
                        Text(address)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#94A8BC"))
                            .padding(.leading, 4)
                            .padding(.top, 4)
                    }
                    
                    Spacer()
                    
                    if recentlyEdited {
                        Text("Recently Edited")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#4F83AB"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#3FA9F5").opacity(0.15))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(hex: "#4F83AB"), lineWidth: 1)
                            )
                    }
                }
                
                Text(subtitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#94A8BC"))
                    .padding(.bottom, 8)
                
                ForEach(reminders, id: \.self) { reminder in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: "#4A60B2"))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().stroke(Color(hex: "#94A8BC").opacity(0.5), lineWidth: 1)
                            )
                        Text(reminder)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#1D3557"))
                    }
                }
                
                if extraCount > 0 {
                    Text("+\(extraCount) more")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#368BC8"))
                        .padding(.leading, 22)
                        .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .cornerRadius(24)
        .shadow(color: Color(hex: "#1D3557").opacity(0.1), radius: 10, y: 5)
    }
}

#Preview {
    NavigationStack {
        LocationView()
    }
}
