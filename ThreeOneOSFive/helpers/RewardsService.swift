import Foundation

// MARK: - VINI Rewards Service
// Handles all rewards, referrals, and trust system API calls

final class RewardsService {
    static let shared = RewardsService()
    
    private let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    // MARK: - Rewards Summary
    
    struct RewardsSummary: Codable {
        let points: Int
        let permanence: Permanence
        let nextReward: NextReward?
        
        struct Permanence: Codable {
            let months: Int
            let days: Int
            let totalDays: Int
        }
        
        struct NextReward: Codable {
            let target: Int?
            let reward: String
        }
    }
    
    func fetchRewardsSummary() async throws -> RewardsSummary {
        let url = URL(string: "\(workerURL)/api/app/rewards")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewardsError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw RewardsError.unauthorized
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RewardsError.networkError
        }
        
        return try JSONDecoder().decode(RewardsSummary.self, from: data)
    }
    
    // MARK: - Rewards History
    
    struct RewardsHistory: Codable {
        let transactions: [Transaction]
        
        struct Transaction: Codable, Identifiable {
            var id: String { UUID().uuidString }
            let type: String
            let points: Int
            let daysAdded: Int
            let description: String
            let createdAt: String
            
            enum CodingKeys: String, CodingKey {
                case type, points, description
                case daysAdded = "days_added"
                case createdAt = "created_at"
            }
        }
    }
    
    func fetchRewardsHistory() async throws -> RewardsHistory {
        let url = URL(string: "\(workerURL)/api/app/rewards/history")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewardsError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw RewardsError.unauthorized
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RewardsError.networkError
        }
        
        return try JSONDecoder().decode(RewardsHistory.self, from: data)
    }
    
    // MARK: - Submit Daily Status
    
    struct StatusResponse: Codable {
        let success: Bool
        let pointsAwarded: Int
        let newPoints: Int
        let message: String
    }
    
    func submitDailyStatus(patchId: String, status: String) async throws -> StatusResponse {
        let url = URL(string: "\(workerURL)/api/app/rewards/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: String] = [
            "patchId": patchId,
            "status": status
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewardsError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw RewardsError.unauthorized
        }
        
        if httpResponse.statusCode == 409 {
            throw RewardsError.alreadyReported
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RewardsError.networkError
        }
        
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }
    
    // MARK: - Referral Info
    
    struct ReferralInfo: Codable {
        let referralCode: String
        let referredBy: String?
        let referralsMade: Int
        let referralsConfirmed: Int
        let daysEarned: Int
        
        enum CodingKeys: String, CodingKey {
            case referralCode = "referralCode"
            case referredBy = "referredBy"
            case referralsMade = "referralsMade"
            case referralsConfirmed = "referralsConfirmed"
            case daysEarned = "daysEarned"
        }
    }
    
    func fetchReferralInfo() async throws -> ReferralInfo {
        let url = URL(string: "\(workerURL)/api/app/referral")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewardsError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw RewardsError.unauthorized
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RewardsError.networkError
        }
        
        return try JSONDecoder().decode(ReferralInfo.self, from: data)
    }
    
    // MARK: - Trust Index
    
    struct TrustIndex: Codable {
        let trustPercentage: Int
        let trustLevel: String
        let distribution: Distribution
        let totalReports: Int
        
        struct Distribution: Codable {
            let safe: Int
            let caution: Int
            let mediumRisk: Int
            let highRisk: Int
            let notRecommended: Int
            
            enum CodingKeys: String, CodingKey {
                case safe, caution
                case mediumRisk = "medium_risk"
                case highRisk = "high_risk"
                case notRecommended = "not_recommended"
            }
        }
    }
    
    func fetchTrustIndex() async throws -> TrustIndex {
        let url = URL(string: "\(workerURL)/api/app/trust")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RewardsError.networkError
        }
        
        return try JSONDecoder().decode(TrustIndex.self, from: data)
    }
    
    // MARK: - Trust Patches
    
    struct TrustPatch: Codable, Identifiable {
        let id: String
        let name: String
        let description: String
        let trustPercentage: Int
        let distribution: TrustIndex.Distribution
        let totalReports: Int
        let alreadyReportedToday: Bool
    }
    
    struct TrustPatchesResponse: Codable {
        let patches: [TrustPatch]
    }
    
    func fetchTrustPatches() async throws -> [TrustPatch] {
        let url = URL(string: "\(workerURL)/api/app/trust/patches")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewardsError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw RewardsError.unauthorized
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RewardsError.networkError
        }
        
        let decoded = try JSONDecoder().decode(TrustPatchesResponse.self, from: data)
        return decoded.patches
    }
}

// MARK: - Errors

enum RewardsError: LocalizedError {
    case networkError
    case unauthorized
    case alreadyReported
    
    var errorDescription: String? {
        switch self {
        case .networkError: return "Error de conexión"
        case .unauthorized: return "Sesión expirada"
        case .alreadyReported: return "Ya reportaste hoy"
        }
    }
}
