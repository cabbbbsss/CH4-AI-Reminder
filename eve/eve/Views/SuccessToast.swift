import SwiftUI

/// The brief confirmation the Location tab shows after a change.
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
