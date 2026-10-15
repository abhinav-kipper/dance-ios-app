import SwiftUI
import SwiftData
import RepasoCore

struct ImportSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    private var importer: ImportCoordinator { env.importer }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(importer.items.count == 1 ? "Importing 1 video" : "Importing \(importer.items.count) videos")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(importer.overallProgress * 100))%")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
            }
            .padding(.top, 28)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(importer.items) { item in row(item) }
                }
            }

            PrimarySheetButton(title: importer.isRunning ? "Hide" : "Done") { dismiss() }
                .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet()
    }

    private func row(_ item: ImportCoordinator.Item) -> some View {
        HStack(spacing: 12) {
            PosterView(request: item.poster, cornerRadius: 8)
                .frame(width: 46, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(detail(item))
                    .font(.system(size: 12))
                    .foregroundStyle(item.state.isFailure ? Theme.rose : Theme.textSecondary)
            }
            Spacer()
            switch item.state {
            case .failed:
                Button {
                    importer.retry(item.id, context: ctx, env: env)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .frame(width: 44, height: 44)
                        .background(Theme.roseTint, in: Circle())
                }
                .accessibilityLabel("Retry import")
            case .copying(let p):
                ProgressRing(progress: p, done: false)
            case .waiting:
                ProgressRing(progress: 0, done: false)
            case .done:
                ProgressRing(progress: 1, done: true)
            }
        }
        .padding(10)
        .cardGlass(radius: 18)
    }

    private func detail(_ item: ImportCoordinator.Item) -> String {
        if case .failed(let message) = item.state { return message }
        var parts: [String] = []
        if let d = item.duration { parts.append(TimeFormat.duration(d)) }
        if let s = item.size { parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)) }
        return parts.isEmpty ? "Waiting…" : parts.joined(separator: " · ")
    }
}

private extension ImportCoordinator.Item.State {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
