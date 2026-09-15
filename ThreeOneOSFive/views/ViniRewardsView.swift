import SwiftUI

/// VINI Rewards tab - Points, trust index, referrals, and rewards
struct ViniRewardsView: View {
    @StateObject private var viewModel = RewardsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero section - Points
                heroSection
                
                // Progress to next reward
                progressSection
                
                // Grid stats
                statsGrid
                
                // Referral card
                referralCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("VINI Rewards")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadRewards()
        }
        .refreshable {
            await viewModel.loadRewards()
        }
    }
    
    // MARK: - Hero Section
    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.accent)
            
            Text(viewModel.formattedPoints)
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(AppTheme.chromeHighlight)
            
            Text("VINI POINTS")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.accentSecondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Text("rewards.next_reward")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textMuted)
                
                Spacer()
                
                Text("\(viewModel.progressPercent)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.bgTertiary)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentSecondary, AppTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(viewModel.progressPercent) / 100, height: 8)
                }
            }
            .frame(height: 8)
            
            // Next reward info
            if let nextReward = viewModel.nextReward {
                Text("rewards.points_remaining \(nextReward.pointsRemaining)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textMuted)
                    .multilineTextAlignment(.center)
                +
                Text(" \(nextReward.rewardName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(18)
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Stats Grid
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            StatCard(
                icon: "flame.fill",
                value: "\(viewModel.streakDays)",
                label: "rewards.streak_days"
            )
            
            StatCard(
                icon: "shield.checkered",
                value: "\(viewModel.trustPercent)%",
                label: "rewards.trust"
            )
            
            StatCard(
                icon: "chart.bar.fill",
                value: "\(viewModel.totalReports)",
                label: "rewards.reports"
            )
            
            StatCard(
                icon: "person.2.fill",
                value: "\(viewModel.referralsCount)",
                label: "rewards.referrals"
            )
        }
    }
    
    // MARK: - Referral Card
    private var referralCard: some View {
        VStack(spacing: 12) {
            Text("rewards.invite_friends")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.chromeHighlight)
            
            Text(viewModel.referralCode)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.accent)
            
            Button {
                viewModel.shareReferralCode()
            } label: {
                Text("rewards.share_code")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.pageBackground)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Stat Card
private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.accent)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.chromeHighlight)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - View Model
@MainActor
class RewardsViewModel: ObservableObject {
    @Published var points: Int = 0
    @Published var streakDays: Int = 0
    @Published var trustPercent: Int = 0
    @Published var totalReports: Int = 0
    @Published var referralsCount: Int = 0
    @Published var progressPercent: Int = 0
    @Published var nextReward: NextReward?
    @Published var referralCode: String = "VINI-XXXX"
    @Published var isLoading: Bool = false
    
    struct NextReward {
        let pointsRemaining: Int
        let rewardName: String
    }
    
    var formattedPoints: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: points)) ?? "\(points)"
    }
    
    func loadRewards() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Load rewards summary
            let summary = try await RewardsService.shared.fetchRewardsSummary()
            points = summary.points
            streakDays = summary.streakDays ?? 0
            
            // Load trust index
            let trust = try await RewardsService.shared.fetchTrustIndex()
            trustPercent = trust.trustPercentage
            
            // Load referral info
            let referral = try await RewardsService.shared.fetchReferralInfo()
            referralsCount = referral.referralsConfirmed
            referralCode = referral.referralCode
            
            // Calculate stats
            totalReports = trust.totalReports
            
            // Calculate progress
            if let target = summary.nextRewardTarget {
                let remaining = max(0, target - points)
                progressPercent = min(100, Int(Double(points) / Double(target) * 100))
                nextReward = NextReward(
                    pointsRemaining: remaining,
                    rewardName: summary.nextRewardName ?? ""
                )
            }
        } catch {
            print("Failed to load rewards: \(error)")
        }
    }
    
    func shareReferralCode() {
        let text = "rewards.share_text \(referralCode)"
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    NavigationStack {
        ViniRewardsView()
    }
}
