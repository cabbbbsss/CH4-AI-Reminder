import SwiftUI

struct PermissionView: View {
    @Binding var currentStep: Int
    @Bindable var permissionManager = PermissionManager.shared
    
    var body: some View {
        ZStack {
            Color(hex: "#1D3557").ignoresSafeArea()
            
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 800, height: 500)
                .blur(radius: 150)
                .position(x: 200, y: 150)
                .ignoresSafeArea(edges: .all)
            
            VStack(alignment: .leading, spacing: 0) {
                Text("Enhance \nYour Assistant")
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundColor(Color(hex: "#1D3557"))
                    .padding(.top, 60)
                    .padding(.horizontal, 24)
                
                Text("EVE works by understanding your world to remind you. All data stored on your device, never anywhere else.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.black.opacity(0.8))
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        PermissionRow(
                            icon: "apple.intelligence",
                            iconColor: Color(hex: "#368BC8"),
                            title: "Apple Intelligence",
                            description: "EVE builds unique patterns from your data.",
                            isGranted: permissionManager.isAIEnabled
                        ) {
                            permissionManager.enableAI()
                        }
                        
                        PermissionRow(
                            icon: "location.fill",
                            iconColor: Color(hex: "#368BC8"),
                            title: "Location Reminders",
                            description: "EVE contextually reminds you at specific places.",
                            isGranted: permissionManager.isLocationGranted
                        ) {
                            permissionManager.requestLocation()
                        }
                        
                        PermissionRow(
                            icon: "bell.badge.fill",
                            iconColor: Color(hex: "#368BC8"),
                            title: "Proactive Notifications",
                            description: "Receives timely habit predictions and reminders.",
                            isGranted: permissionManager.isNotificationsGranted
                        ) {
                            Task { await permissionManager.requestNotifications() }
                        }
                        
                        PermissionRow(
                            icon: "calendar",
                            iconColor: Color(hex: "#368BC8"),
                            title: "Calendar & Reminders",
                            description: "Learns your schedules to avoid duplicate reminders.",
                            isGranted: permissionManager.isCalendarGranted && permissionManager.isReminderGranted
                        ) {
                          Task { await permissionManager.requestCalendar(); await permissionManager.requestReminders() }
                          
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                    .padding(.bottom, 20) // Space for floating button
                }
            }
            
            // Floating Next Button
                    Button {
                        withAnimation {
                            currentStep = 2
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundStyle(Color.primary)
                            .padding(5)
                    }
                    .buttonStyle(.glassProminent)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(30)
                    .disabled(!allPermissionsGranted) // Optional: disable if not all granted? The original design had "Continue" or "Skip". Let's allow skipping by not disabling it.
                }
            }
        

    
    var allPermissionsGranted: Bool {
        permissionManager.isAIEnabled && permissionManager.isLocationGranted && permissionManager.isNotificationsGranted && permissionManager.isCalendarGranted
    }
}

struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "#1D3557"))
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "#1D3557"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "#30D158"))
                    .font(.system(size: 24))
            } else {
                Button(action: {
                    withAnimation {
                        action()
                    }
                }) {
                    Text("Allow")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color(hex: "#368BC8"))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .background(Color(hex: "#E8F3FF"))
        .cornerRadius(20)
    }
}

#Preview {
    PermissionView(currentStep: .constant(1))
}
