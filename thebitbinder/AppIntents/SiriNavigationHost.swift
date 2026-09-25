import SwiftUI
import SwiftData
import UIKit

/// A Siri command may arrive while a draft sheet is already open. Present from
/// the active scene's top controller so that draft stays intact underneath.
/// This is the single presentation boundary for foreground App Intents.
struct SiriNavigationHost: UIViewControllerRepresentable {
    @ObservedObject var router: SiriNavigationRouter
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var userPreferences: UserPreferences
    let isReady: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.configure(router: router, container: modelContext.container,
                             preferences: userPreferences, isReady: isReady)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.presentationTask?.cancel()
    }

    @MainActor
    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        fileprivate var presentationTask: Task<Void, Never>?
        private var activeRequestID: UUID?
        private weak var router: SiriNavigationRouter?
        private var isReady = false
        private var container: ModelContainer?
        private var preferences: UserPreferences?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            schedulePresentation()
        }

        func configure(router: SiriNavigationRouter, container: ModelContainer,
                       preferences: UserPreferences, isReady: Bool) {
            self.router = router
            self.container = container
            self.preferences = preferences
            self.isReady = isReady
            schedulePresentation()
        }

        private func schedulePresentation() {
            guard presentationTask == nil, activeRequestID == nil, isReady,
                  router?.requests.first != nil else { return }
            presentationTask = Task { @MainActor [weak self] in
                // Yield out of SwiftUI's update before presenting a controller.
                await Task.yield()
                while let self, !Task.isCancelled, self.isReady {
                    if self.presentNextIfPossible() { break }
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                }
                self?.presentationTask = nil
            }
        }

        private func presentNextIfPossible() -> Bool {
            guard let request = router?.requests.first,
                  let container, let preferences else { return true }
            guard let window = view.window,
                  window.windowScene?.activationState == .foregroundActive,
                  var presenter = window.rootViewController else { return false }
            while let presented = presenter.presentedViewController {
                guard !presented.isBeingDismissed else { return false }
                presenter = presented
            }
            guard !presenter.isBeingPresented, !presenter.isBeingDismissed,
                  !(presenter is UIAlertController) else { return false }

            let destination = SiriDestinationView(request: request, container: container,
                                                  preferences: preferences)
            let hosting = DestinationController(rootView: destination)
            hosting.view.accessibilityIdentifier = "siri.destination"
            hosting.modalPresentationStyle = .pageSheet
            hosting.presentationController?.delegate = self
            activeRequestID = request.id
            // SwiftUI's dismiss action and an interactive swipe both report here.
            hosting.onDismiss = { [weak self] in self?.finish(request.id) }
            presenter.present(hosting, animated: true)
            return true
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            if let activeRequestID { finish(activeRequestID) }
        }

        private func finish(_ requestID: UUID) {
            guard activeRequestID == requestID else { return }
            activeRequestID = nil
            router?.finish(requestID)
            schedulePresentation()
        }
    }

    @MainActor
    final class DestinationController: UIHostingController<SiriDestinationView> {
        var onDismiss: (() -> Void)?

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            // A child editor or full-screen cover can hide this controller
            // without dismissing it. Only consume the request on dismissal.
            if presentingViewController == nil { onDismiss?() }
        }
    }
}
