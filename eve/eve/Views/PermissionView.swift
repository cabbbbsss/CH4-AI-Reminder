import SwiftUI
import UIKit

struct PermissionView: View {
    @Binding var currentStep: Int
    @Bindable var permissionManager = PermissionManager.shared

    /// Guards against double-taps while the OS prompts are being presented.
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            Color(.bgPrimary).ignoresSafeArea()

            Rectangle()
                .fill(Color.bgSecondary.opacity(0.8))
                .frame(width: 800, height: 500)
                .blur(radius: 150)
                .position(x: 200, y: 150)
                .ignoresSafeArea(edges: .all)

            VStack(alignment: .leading, spacing: 0) {
                Text("Enhance \nYour Assistant")
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundColor(Color(.textPrimary))
                    .padding(.top, 60)
                    .padding(.horizontal, 39)

                Text("EVE works by understanding your world to remind you. All data stored on your device, never anywhere else.")
                    .font(.system(size: 15, weight: .medium))
                    .opacity(0.7)
                    .foregroundColor(Color(.textPrimary))
                    .padding(.top, 10)
                    .padding(.horizontal, 39)

                // These rows only explain what EVE will access. The actual
                // iOS permission prompts are requested when the user taps Next.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        PermissionRow(
                            icon: "apple.intelligence",
                            iconColor: Color.accentColor,
                            title: "Apple Intelligence",
                            description: "Automatically creates personalised reminders for your days, based on your data and context."
                        )

                        PermissionRow(
                            icon: "location.fill",
                            iconColor: Color.accentColor,
                            title: "Location",
                            description: "Get reminders when you are at specific places."
                        )
                        
                        PermissionRow(
                            icon: "calendar",
                            iconColor: Color.accentColor,
                            title: "Calendar & Reminders",
                            description: "Get reminders based on your past and upcoming events and schedule."
                        )

                        PermissionRow(
                            icon: "bell.badge.fill",
                            iconColor: Color.accentColor,
                            title: "Notifications",
                            description: "Receives timely nudges and heads-ups so you’re always prepared."
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                    .padding(.bottom, 20) // Space for floating button
                }
            }

            // Floating Next Button
            Button {
                requestPermissionsThenContinue()
            } label: {
                Group {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(Color(.textPrimary))
                .frame(width: 26, height: 26)
                .padding(10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .background(Color(.bgSecondary))
            .clipShape(Circle())
            .disabled(isRequesting)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding()
        }
    }

    private func requestPermissionsThenContinue() {
        guard !isRequesting else { return }
        isRequesting = true

        Task {
            // Present the OS prompts one at a time, then move on regardless
            // of the answers — permissions are the user's choice.
            await permissionManager.requestAllPermissions()
            isRequesting = false
            withAnimation {
                currentStep = 2
            }
        }
    }
}

/// Informational only: shows what kind of data EVE wants to access.
struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(iconColor)
                .frame(width: 30)
                .padding(.trailing, 10)
                .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(.textPrimary))

                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .background(Color(.bgSecondary))
        .cornerRadius(20)
    }
}

#Preview {
    PermissionView(currentStep: .constant(1))
}
