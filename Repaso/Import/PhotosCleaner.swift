import Photos

/// Removes imported videos from Photos (iOS asks the user to confirm with its own alert).
enum PhotosCleaner {
    enum Outcome { case removed, kept, needsAccess, failed }

    static func delete(_ ids: [String]) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return .needsAccess }
        // Under limited access only the assets the user shared are visible.
        guard PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count > 0 else { return .needsAccess }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
            }
            return .removed
        } catch {
            return (error as? PHPhotosError)?.code == .userCancelled ? .kept : .failed
        }
    }
}
