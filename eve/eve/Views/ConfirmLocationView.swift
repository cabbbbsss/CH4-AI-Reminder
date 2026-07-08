import SwiftUI
import MapKit

// MARK: - Confirm Location on map (Sketch artboard 25FF8DB0)

struct ConfirmLocationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsScaffold(title: "Add New Address") {
            VStack(spacing: 20) {
                ZStack {
                    Map()
                        .frame(maxWidth: .infinity)
                        .frame(height: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    Image(systemName: "mappin")
                        .font(.system(size: 32))
                        .foregroundColor(Color(hex: "#FF4245"))
                        .offset(y: -16)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 20)

                Button {
                    dismiss()
                } label: {
                    Text("Confirm Location")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#E0ECF7"))
                        .frame(width: 200, height: 40)
                        .background(Color(hex: "#368BC8"))
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    NavigationStack {
        ConfirmLocationView()
    }
}
