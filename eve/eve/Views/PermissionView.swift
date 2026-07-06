import SwiftUI

struct PermissionView: View {
  @Binding var currentStep: Int
  @Bindable var permissionManager = PermissionManager.shared
  
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Enhance Your Assistant")
        .font(.largeTitle)
        .fontWeight(.bold)
        .padding(.top, 40)
      
      Text("To provide contextual reminders, the AI needs to understand your environment.")
        .foregroundStyle(.secondary)
      
      ScrollView {
        VStack(spacing: 25) {
          PermissionRow(icon: "brain", title: "Apple Intelligence", description: "Enables on-device Foundation Models to learn your patterns privately.", isGranted: permissionManager.isAIEnabled) {
            permissionManager.enableAI()
          }
          
          PermissionRow(icon: "location.fill", title: "Location Services", description: "Allows the assistant to know when you leave home or arrive at work.", isGranted: permissionManager.isLocationGranted) {
            permissionManager.requestLocation()
          }
          
          PermissionRow(icon: "bell.badge.fill", title: "Notifications", description: "Lets the assistant alert you with adaptive reminders.", isGranted: permissionManager.isNotificationsGranted) {
            Task { await permissionManager.requestNotifications() }
          }
          
          PermissionRow(icon: "calendar", title: "Calendar & Reminders", description: "Learns your schedules to avoid duplicate reminders.", isGranted: permissionManager.isCalendarGranted) {
            Task { await permissionManager.requestCalendar() }
          }
        }
        .padding(.vertical)
      }
      
      Button {
        withAnimation {
          currentStep = 2
        }
      } label: {
        Text(allPermissionsGranted ? "Continue" : "Skip for now")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding()
          .background(allPermissionsGranted ? Color.blue : Color.gray.opacity(0.3))
          .foregroundColor(allPermissionsGranted ? .white : .primary)
          .cornerRadius(15)
      }
      .padding(.bottom, 30)
    }
    .padding(.horizontal, 25)
  }
  
  var allPermissionsGranted: Bool {
    permissionManager.isAIEnabled && permissionManager.isLocationGranted && permissionManager.isNotificationsGranted && permissionManager.isCalendarGranted
  }
}

struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let isGranted: Bool
  let action: () -> Void
  
  var body: some View {
    HStack(spacing: 15) {
      Image(systemName: icon)
        .font(.title)
        .foregroundColor(isGranted ? .green : .blue)
        .frame(width: 40)
      
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.headline)
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      
      Spacer()
      
      if isGranted {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
          .font(.title2)
      } else {
        Button("Allow") {
          action()
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
      }
    }
    .padding()
    .background(.ultraThinMaterial)
    .cornerRadius(15)
  }
}
