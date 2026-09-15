import SwiftUI

/// Maintenance mode screen with animated gears design
struct MaintenanceView: View {
    let message: String
    let eta: String?
    
    @State private var rotation1: Double = 0
    @State private var rotation2: Double = 0
    
    init(message: String, eta: String? = nil) {
        self.message = message
        self.eta = eta
    }
    
    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Animated gears container
                ZStack {
                    // Outer gear - dashed circle
                    Circle()
                        .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(rotation1))
                    
                    // Inner gear - dotted circle
                    Circle()
                        .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 4, dash: [2, 4]))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(rotation2))
                    
                    // Center circle with icon
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.pageBackground)
                        )
                }
                .frame(width: 120, height: 120)
                
                Spacer().frame(height: 32)
                
                // Title
                Text("VINI PRIVATE")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.chromeHighlight)
                
                Spacer().frame(height: 8)
                
                // Subtitle
                Text("maintenance.updating")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                
                Spacer().frame(height: 16)
                
                // Message
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.accentSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Divider
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 60, height: 2)
                    .padding(.vertical, 20)
                
                // ETA
                if let eta = eta {
                    Text(eta)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                }
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                rotation1 = 360
            }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                rotation2 = -360
            }
        }
    }
}

#Preview {
    MaintenanceView(
        message: "Nuevas funciones y mejoras están en camino.",
        eta: "Tiempo estimado: 30 minutos"
    )
}
