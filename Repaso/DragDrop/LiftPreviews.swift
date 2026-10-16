import SwiftUI
import RepasoCore

// Drag previews render outside the view hierarchy, so they take plain values and no environment objects.

/// Lifted folder card: scale 1.07, −3°, deep shadow, 1pt outline.
struct FolderLiftPreview: View {
    let name: String
    let clipCount: Int
    let reduceMotion: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.folderCard, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(clipCount == 1 ? "1 clip" : "\(clipCount) clips")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(width: 168, height: 150, alignment: .leading)
        .background(Color(red: 0.13, green: 0.13, blue: 0.15), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .scaleEffect(reduceMotion ? 1 : 1.07)
        .rotationEffect(.degrees(reduceMotion ? 0 : -3))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .padding(28)
    }
}

/// Lifted clip row: scale 1.04, −2.5°, deep shadow, 1pt outline.
struct ClipLiftPreview: View {
    let name: String
    let length: Double
    let reduceMotion: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "film")
                .foregroundStyle(Theme.accent)
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(TimeFormat.duration(length))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(width: 280, height: 60)
        .background(Color(red: 0.13, green: 0.13, blue: 0.15), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .scaleEffect(reduceMotion ? 1 : 1.04)
        .rotationEffect(.degrees(reduceMotion ? 0 : -2.5))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .padding(24)
    }
}
