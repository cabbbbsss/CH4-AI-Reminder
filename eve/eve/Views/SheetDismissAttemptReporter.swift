//
//  SheetDismissAttemptReporter.swift
//  Eve
//

import SwiftUI
import UIKit

/// Reports when the user tries to swipe away a sheet that is holding unsaved
/// work, so the sheet can explain itself instead of just refusing to move.
///
/// SwiftUI can *block* an interactive dismiss (`interactiveDismissDisabled`)
/// but offers no hook for one being attempted — the sheet simply rubber-bands
/// and the user is told nothing. UIKit does have that hook
/// (`presentationControllerDidAttemptToDismiss`), so this puts an empty view
/// controller inside the sheet purely to reach its presentation controller.
///
/// The delegate is installed **only while guarded**, and the previous one is
/// put back the moment it isn't. That matters: SwiftUI relies on
/// `presentationControllerDidDismiss` to reset the binding that presented the
/// sheet, so permanently holding the delegate would let a sheet be swiped away
/// while its `isPresented` stayed true — leaving it unable to open again.
struct SheetDismissAttemptReporter: UIViewControllerRepresentable {

    /// True when there is unsaved work to protect.
    var isGuarded: Bool

    var onAttempt: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {

        context.coordinator.onAttempt = onAttempt

        // The hosting controller isn't attached on the first layout pass.
        DispatchQueue.main.async {
            guard let host = controller.parent else { return }

            host.isModalInPresentation = isGuarded

            guard let presentation = host.presentationController else { return }

            if isGuarded {
                if presentation.delegate !== context.coordinator {
                    context.coordinator.previousDelegate = presentation.delegate
                    presentation.delegate = context.coordinator
                }
            } else if presentation.delegate === context.coordinator {
                presentation.delegate = context.coordinator.previousDelegate
                context.coordinator.previousDelegate = nil
            }
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {

        var onAttempt: () -> Void = {}

        /// Whoever owned the delegate before we borrowed it — normally SwiftUI.
        weak var previousDelegate: (any UIAdaptivePresentationControllerDelegate)?

        func presentationControllerDidAttemptToDismiss(
            _ presentationController: UIPresentationController
        ) {
            onAttempt()
        }
    }
}
