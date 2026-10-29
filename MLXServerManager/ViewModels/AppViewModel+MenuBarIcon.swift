import Foundation

/// What the menu bar icon shows: outline = off, filled = on, arrows = busy,
/// arrow-out = a server is running outside the app (nothing managed is running).
nonisolated enum MenuBarIconState: Equatable, Sendable {
    case off
    case external
    case busy
    case on

    var symbolName: String {
        switch self {
        case .on: "bolt.circle.fill"
        case .busy: "arrow.triangle.2.circlepath.circle"
        case .external: "arrow.up.right.circle"
        case .off: "bolt.circle"
        }
    }

    /// Managed state always wins; external servers only change an otherwise idle icon.
    func withExternalServers(_ hasExternalServers: Bool) -> MenuBarIconState {
        self == .off && hasExternalServers ? .external : self
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
