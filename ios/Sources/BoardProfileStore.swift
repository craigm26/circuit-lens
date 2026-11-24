import Foundation
import UIKit

/// Persists scanned BoardProfiles and their multi-angle JPEG photos locally in Documents/BoardProfiles.
@MainActor
public final class BoardProfileStore: ObservableObject {
    @Published public private(set) var profiles: [BoardProfile] = []

    private let baseDir: URL

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.baseDir = docs.appendingPathComponent("BoardProfiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        loadAll()
    }

    public func loadAll() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: nil
        ) else {
            profiles = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let loaded: [BoardProfile] = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(BoardProfile.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        self.profiles = loaded
    }

    /// Save a JPEG photo angle into the store and return its filename.
    public func savePhoto(_ image: UIImage, profileID: UUID) -> String? {
        let filename = "\(profileID.uuidString)-\(UUID().uuidString.prefix(8)).jpg"
        let url = baseDir.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.80) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    public func loadPhoto(filename: String) -> UIImage? {
        let url = baseDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    public func save(_ profile: BoardProfile) {
        var updated = profile
        updated.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let url = baseDir.appendingPathComponent("\(updated.id.uuidString).json")
        if let data = try? encoder.encode(updated) {
            try? data.write(to: url, options: .atomic)
        }

        if let idx = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[idx] = updated
        } else {
            profiles.insert(updated, at: 0)
        }
        profiles.sort { $0.updatedAt > $1.updatedAt }
    }

    public func delete(_ profile: BoardProfile) {
        let jsonURL = baseDir.appendingPathComponent("\(profile.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)
        for photo in profile.photos {
            let imgURL = baseDir.appendingPathComponent(photo.imageFilename)
            try? FileManager.default.removeItem(at: imgURL)
        }
        profiles.removeAll { $0.id == profile.id }
    }
}
