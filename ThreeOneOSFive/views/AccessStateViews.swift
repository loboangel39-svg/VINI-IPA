import SwiftUI

struct PausedLicenseView: View {
    let accessState: ServerAccessState?
    let onRefresh: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AccessStateScreen(
            title: "Licencia pausada",
            message: "Tu licencia está temporalmente pausada. El tiempo restante se encuentra congelado y se conservará hasta su reactivación.",
            systemImage: "pause.circle.fill",
            detail: frozenTime,
            onRefresh: onRefresh
        )
        .onChange(of: scenePhase) { phase in
            if phase == .active { onRefresh() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                onRefresh()
            }
        }
    }

    private var frozenTime: String? {
        guard let seconds = accessState?.frozenSeconds else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        return "Tiempo conservado: \(days)d \(hours)h \(minutes)m"
    }
}

struct MaintenanceView: View {
    let accessState: ServerAccessState?
    let onRefresh: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AccessStateScreen(
            title: "VINI en mantenimiento",
            message: accessState?.maintenanceMessage?.isEmpty == false
                ? accessState!.maintenanceMessage!
                : "VINI-IPA se encuentra temporalmente en mantenimiento. Tu tiempo de licencia está protegido y volverá a transcurrir cuando finalice la suspensión.",
            systemImage: "wrench.and.screwdriver.fill",
            detail: "Estado de servicio: mantenimiento",
            onRefresh: onRefresh
        )
        .onChange(of: scenePhase) { phase in
            if phase == .active { onRefresh() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                onRefresh()
            }
        }
    }
}

private struct AccessStateScreen: View {
    let title: String
    let message: String
    let systemImage: String
    let detail: String?
    let onRefresh: () -> Void
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
                if let detail {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    onRefresh()
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        isRefreshing = false
                    }
                } label: {
                    Label("Verificar estado", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
                if isRefreshing { ProgressView() }
            }
            .padding(28)
        }
    }
}
