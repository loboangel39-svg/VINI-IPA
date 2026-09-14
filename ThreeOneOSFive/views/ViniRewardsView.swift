import SwiftUI

// MARK: - VINI Rewards View
// Replaces the Config tab with the rewards system

struct ViniRewardsView: View {
    @State private var rewardsSummary: RewardsService.RewardsSummary?
    @State private var rewardsHistory: RewardsService.RewardsHistory?
    @State private var referralInfo: RewardsService.ReferralInfo?
    @State private var trustIndex: RewardsService.TrustIndex?
    @State private var trustPatches: [RewardsService.TrustPatch] = []
    @State private var isLoading = true
    @State private var showStatusSheet = false
    @State private var selectedPatch: RewardsService.TrustPatch?
    @State private var statusMessage: String?
    @State private var showCopiedAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with points
                    headerSection
                    
                    // Trust Index
                    trustSection
                    
                    // Rewards
                    rewardsSection
                    
                    // Referrals
                    referralSection
                    
                    // Permanence
                    permanenceSection
                    
                    // History
                    historySection
                }
                .padding()
            }
            .navigationTitle("VINI Rewards")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadData()
            }
            .sheet(isPresented: $showStatusSheet) {
                if let patch = selectedPatch {
                    StatusReportSheet(patch: patch) { status in
                        await submitStatus(patchId: patch.id, status: status)
                    }
                    .presentationDetents([.medium])
                }
            }
            .alert("Copiado", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Código de referido copiado al portapapeles")
            }
            .task {
                await loadData()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.accent)
            
            Text(formattedPoints)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppTheme.chromeHighlight)
            
            Text("VINI Points")
                .font(.subheadline)
                .foregroundStyle(AppTheme.accentSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var formattedPoints: String {
        let points = rewardsSummary?.points ?? 0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: points)) ?? "\(points)"
    }
    
    // MARK: - Trust Section
    
    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Índice de confianza", systemImage: "shield.checkered")
                .font(.headline)
                .foregroundStyle(AppTheme.chromeHighlight)
            
            if let trust = trustIndex {
                HStack(spacing: 16) {
                    VStack {
                        Text("\(trust.trustPercentage)%")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(trustColor(for: trust.trustPercentage))
                        Text(trust.trustLevel)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentSecondary)
                    }
                    
                    Divider()
                        .frame(height: 50)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        trustRow("Seguro", count: trust.distribution.safe, color: .green)
                        trustRow("Precaución", count: trust.distribution.caution, color: .yellow)
                        trustRow("Riesgo medio", count: trust.distribution.mediumRisk, color: .orange)
                        trustRow("Alto riesgo", count: trust.distribution.highRisk, color: .red)
                        trustRow("No recomendado", count: trust.distribution.notRecommended, color: .black)
                    }
                }
                
                Button {
                    Task {
                        trustPatches = (try? await RewardsService.shared.fetchTrustPatches()) ?? []
                        showStatusSheet = true
                    }
                } label: {
                    Text("Ver estados de patches")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(AppTheme.accent)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func trustRow(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.accentSecondary)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.chromeHighlight)
        }
    }
    
    private func trustColor(for percentage: Int) -> Color {
        switch percentage {
        case 90...: return .green
        case 70..<90: return .yellow
        case 50..<70: return .orange
        case 30..<50: return .red
        default: return .black
        }
    }
    
    // MARK: - Rewards Section
    
    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mis recompensas", systemImage: "gift.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.chromeHighlight)
            
            if let summary = rewardsSummary, let next = summary.nextReward, let target = next.target {
                let remaining = max(0, target - summary.points)
                let progress = Double(summary.points) / Double(target)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Próxima recompensa:")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accentSecondary)
                    
                    HStack {
                        Text("\(target) PTS")
                            .font(.subheadline.weight(.semibold))
                        Text("→")
                            .foregroundStyle(AppTheme.accentSecondary)
                        Text(next.reward)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    
                    ProgressView(value: progress)
                        .tint(AppTheme.accent)
                    
                    Text("\(remaining) puntos restantes")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentSecondary)
                }
            }
        }
        .padding()
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Referral Section
    
    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Referidos", systemImage: "person.2.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.chromeHighlight)
            
            if let referral = referralInfo {
                VStack(spacing: 12) {
                    HStack {
                        Text("Tu código:")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.accentSecondary)
                        Spacer()
                        Text(referral.referralCode)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.chromeHighlight)
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = referral.referralCode
                            showCopiedAlert = true
                        } label: {
                            Label("Copiar", systemImage: "doc.on.doc")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppTheme.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .foregroundStyle(AppTheme.accent)
                        
                        Button {
                            shareReferralCode(referral.referralCode)
                        } label: {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppTheme.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                    
                    HStack(spacing: 20) {
                        referralStat("Realizados", value: referral.referralsMade)
                        referralStat("Confirmados", value: referral.referralsConfirmed)
                        referralStat("Días ganados", value: referral.daysEarned)
                    }
                    .padding(.top, 8)
                    
                    Text("1 referido válido = 7 días gratis")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentSecondary)
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func referralStat(_ label: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.chromeHighlight)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.accentSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func shareReferralCode(_ code: String) {
        let text = "Únete a VINI-IPA usando mi código: \(code)"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var current = rootViewController
            while let presented = current.presentedViewController {
                current = presented
            }
            current.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Permanence Section
    
    private var permanenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tu permanencia", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(AppTheme.chromeHighlight)
            
            if let permanence = rewardsSummary?.permanence {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(permanence.months) meses \(permanence.days) días")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.chromeHighlight)
                    
                    let progress = min(1.0, Double(permanence.totalDays) / 90.0)
                    ProgressView(value: progress)
                        .tint(AppTheme.accent)
                    
                    if permanence.totalDays < 90 {
                        let remaining = 90 - permanence.totalDays
                        Text("Próxima recompensa en \(remaining) días")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentSecondary)
                        Text("🎁 14 días gratis al cumplir 3 meses")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    } else {
                        Text("🎉 ¡3 meses con VINI completados!")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - History Section
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Historial", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .foregroundStyle(AppTheme.chromeHighlight)
            
            if let history = rewardsHistory, !history.transactions.isEmpty {
                ForEach(history.transactions.prefix(10)) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.description)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.chromeHighlight)
                            Text(formatDate(tx.createdAt))
                                .font(.caption)
                                .foregroundStyle(AppTheme.accentSecondary)
                        }
                        
                        Spacer()
                        
                        if tx.points > 0 {
                            Text("+\(tx.points)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        } else if tx.daysAdded > 0 {
                            Text("+\(tx.daysAdded)d")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if tx.id != history.transactions.prefix(10).last?.id {
                        Divider()
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text("Sin transacciones aún")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accentSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(AppTheme.consoleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    // MARK: - Status Report
    
    private func submitStatus(patchId: String, status: String) async {
        do {
            let response = try await RewardsService.shared.submitDailyStatus(patchId: patchId, status: status)
            statusMessage = response.message
            showStatusSheet = false
            await loadData()
        } catch RewardsError.alreadyReported {
            statusMessage = "Ya reportaste este patch hoy"
        } catch {
            statusMessage = "Error al enviar"
        }
    }
    
    // MARK: - Load Data
    
    private func loadData() async {
        isLoading = true
        
        async let summary = RewardsService.shared.fetchRewardsSummary()
        async let history = RewardsService.shared.fetchRewardsHistory()
        async let referral = RewardsService.shared.fetchReferralInfo()
        async let trust = RewardsService.shared.fetchTrustIndex()
        
        do {
            rewardsSummary = try await summary
            rewardsHistory = try await history
            referralInfo = try await referral
            trustIndex = try await trust
        } catch {
            log("rewards: load error - \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}

// MARK: - Status Report Sheet

struct StatusReportSheet: View {
    let patch: RewardsService.TrustPatch
    let onSubmit: (String) async -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: String?
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(patch.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("¿Cuál es tu estado de este patch?")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accentSecondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 12) {
                    statusButton("Seguro", value: "safe", color: .green)
                    statusButton("Precaución", value: "caution", color: .yellow)
                    statusButton("Riesgo medio", value: "medium_risk", color: .orange)
                    statusButton("Alto riesgo", value: "high_risk", color: .red)
                    statusButton("No recomendado", value: "not_recommended", color: .black)
                }
                
                Spacer()
                
                if patch.alreadyReportedToday {
                    Text("Ya reportaste hoy (+5 PTS)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentSecondary)
                } else {
                    Text("Al reportar ganarás +5 VINI Points")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding()
            .navigationTitle("Reportar estado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
    
    private func statusButton(_ label: String, value: String, color: Color) -> some View {
        Button {
            selectedStatus = value
            isSubmitting = true
            Task {
                await onSubmit(value)
                isSubmitting = false
            }
        } label: {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(label)
                    .font(.body.weight(.medium))
                Spacer()
                if selectedStatus == value && isSubmitting {
                    ProgressView()
                }
            }
            .padding()
            .background(selectedStatus == value ? AppTheme.accent.opacity(0.15) : AppTheme.consoleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(AppTheme.chromeHighlight)
        .disabled(isSubmitting || patch.alreadyReportedToday)
    }
}

// MARK: - Preview

#Preview {
    ViniRewardsView()
}
