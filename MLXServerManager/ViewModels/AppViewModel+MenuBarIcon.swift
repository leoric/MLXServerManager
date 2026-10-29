import Foundation

/// What the menu bar icon shows. Mirrors the status icon of a typical
/// menu bar server manager: outline = off, filled = on, arrows = busy.
nonisolated enum MenuBarIconState: Equatable, Sendable {
    case off
    case busy
    case on

    var symbolName: String {
        switch self {
        case .on: "bolt.circle.fill"
        case .busy: "arrow.triangle.2.circlepath.circle"
        case .off: "bolt.circle"
        }
    }
}

extension AppViewModel {
    /// `.on` as soon as any profile is serving, regardless of backend
    /// (Rapid-MLX or mlx_lm): process tracking is keyed by profile, not backend.
    /// `.busy` while a profile is starting, loading or stopping and nothing is
    /// serving yet. `.off` otherwise.
    var menuBarIconState: MenuBarIconState {
        let isAnyModelOn = models.contains { model in
            guard !isModelTransitioning(model) else { return false }
            switch runtimeState(for: model) {
            case .ready, .degraded, .adoptedExternalServer:
                return true
            default:
                return isModelRunning(model)
            }
        }
        if isAnyModelOn {
            return .on
        }
        if models.contains(where: isModelTransitioning) {
            return .busy
        }
        return .off
    }
}
