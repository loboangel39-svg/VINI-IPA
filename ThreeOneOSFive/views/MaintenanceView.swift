import SwiftUI

struct MaintenanceView: View {
    let message: String
    
    @State private var opacity: Double = 0
    @State private var iconScale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Icon
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .scaleEffect(iconScale)
                }
                
                Spacer().frame(height: 32)
                
                // Title
                Text("maintenance.title")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.chromeHighlight)
                    .multilineTextAlignment(.center)
                
                Spacer().frame(height: 12)
                
                // Message
                Text(message)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppTheme.accentSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer().frame(height: 40)
                
                // Subtle indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("maintenance.status")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.accentSecondary)
                }
                
                Spacer()
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                iconScale = 1.05
            }
        }
    }
}

struct MaintenanceView_Previews: PreviewProvider {
    static var previews: some View {
        MaintenanceView(message: "We are performing scheduled maintenance. Please check back later.")
    }
}
