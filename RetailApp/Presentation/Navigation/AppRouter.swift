import Observation

enum AppSheet: String, Identifiable, Sendable {
    case cart

    var id: String { rawValue }
}

/// App-session navigation state. Feature coordinators own destination rendering.
@MainActor
@Observable
final class AppRouter {
    var path: [Destination] = []
    var presentedSheet: AppSheet?

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    func navigateBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func navigateToRoot() {
        path.removeAll()
    }

    func present(_ sheet: AppSheet) {
        presentedSheet = sheet
    }

    func dismissSheet() {
        presentedSheet = nil
    }
}
