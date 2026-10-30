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

/// What the icon needs to know about one model profile.
nonisolated struct MenuBarProfileSnapshot: Equatable, Sendable {
    var runtimeState: ModelRuntimeState
    /// A process started by this app is alive for the profile.
    var isProcessRunning: Bool
    /// The profile is starting, loading, checking readiness or stopping.
    var isTransitioning: Bool
}

extension MenuBarIconState {
    /// `.on` as soon as any profile is serving, regardless of backend
    /// (Rapid-MLX or mlx_lm): process tracking is keyed by profile, not backend.
    /// `.busy` while a profile is starting, loading or stopping and nothing is
    /// serving yet. `.off` otherwise.
    static func resolve(profiles: [MenuBarProfileSnapshot]) -> MenuBarIconState {
        let isAnyProfileOn = profiles.contains { profile in
            guard !profile.isTransitioning else { return false }
            switch profile.runtimeState {
            case .ready, .degraded, .adoptedExternalServer:
                return true
            default:
                return profile.isProcessRunning
            }
        }
        if isAnyProfileOn {
            return .on
        }
        if profiles.contains(where: \.isTransitioning) {
            return .busy
        }
        return .off
    }
}

extension AppViewModel {
    var menuBarIconState: MenuBarIconState {
        MenuBarIconState.resolve(
            profiles: models.map { model in
                MenuBarProfileSnapshot(
                    runtimeState: runtimeState(for: model),
                    isProcessRunning: isModelRunning(model),
                    isTransitioning: isModelTransitioning(model)
                )
            }
        )
    }
}
