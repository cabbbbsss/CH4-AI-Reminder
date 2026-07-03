import SwiftUI

struct SettingsView: View {
  @Bindable var permissionManager = PermissionManager.shared
  
  var body: some View {
    Form {
      Section(header: Text("Permissions")) {
        Toggle("Apple Intelligence", isOn: $permissionManager.isAIEnabled)
        
        HStack {
          Text("Location Services")
          Spacer()
          Text(permissionManager.isLocationGranted ? "Granted" : "Denied")
            .foregroundStyle(permissionManager.isLocationGranted ? .green : .red)
        }
        
        HStack {
          Text("Notifications")
          Spacer()
          Text(permissionManager.isNotificationsGranted ? "Granted" : "Denied")
            .foregroundStyle(permissionManager.isNotificationsGranted ? .green : .red)
        }
        
        HStack {
          Text("Calendar & Reminders")
          Spacer()
          Text(permissionManager.isCalendarGranted ? "Granted" : "Denied")
            .foregroundStyle(permissionManager.isCalendarGranted ? .green : .red)
        }
      }
      
      Section(header: Text("Data & Privacy")) {
        NavigationLink("Learning History") {
          Text("Learning History Placeholder")
            .navigationTitle("History")
        }
        
        Button("Reset AI Learning", role: .destructive) {
          // Reset logic
        }
      }
      
      Section(header: Text("About")) {
        HStack {
          Text("Version")
          Spacer()
          Text("1.0.0")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Settings")
  }
}
