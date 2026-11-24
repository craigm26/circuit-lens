import Foundation
import UIKit

public struct StudioTeardownPayload: Codable {
    public let title: String
    public let level: String
    public let summary: BoardSummaryResult?
    public let lidar: LiDARMeasurement?
    public let photoCount: Int
    public let functionalZones: [String: [String]]
    public let components: [DetectedComponent]
    public let chatTurns: [ChatTurn]
    public let imageBase64JPEG: String?
}

public enum StudioSync {
    public static let defaultEndpoint = "http://pi-nas.local:8088/api/teardowns"

    public static func upload(
        endpoint: String,
        title: String,
        level: LearningLevel,
        summary: BoardSummaryResult?,
        lidar: LiDARMeasurement? = nil,
        photoCount: Int = 1,
        components: [DetectedComponent],
        chatTurns: [ChatTurn],
        image: UIImage?
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        let jpegB64 = image?.jpegData(compressionQuality: 0.78)?.base64EncodedString()
        var zones: [String: [String]] = [:]
        for c in components {
            zones[c.category.functionalZone, default: []].append(c.displayTitle)
        }
        let payload = StudioTeardownPayload(
            title: title,
            level: level.rawValue,
            summary: summary,
            lidar: lidar,
            photoCount: photoCount,
            functionalZones: zones,
            components: components,
            chatTurns: chatTurns,
            imageBase64JPEG: jpegB64
        )
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let savedURL = obj["url"] as? String {
            return savedURL
        }
        return endpoint
    }
}
