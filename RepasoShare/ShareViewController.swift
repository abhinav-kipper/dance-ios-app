import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RepasoCore

/// "Repaso" in the share sheet (Photos, Files, …): copies the shared videos into the App Group inbox, then opens
/// the app, which takes them through the import guide.
final class ShareViewController: UIViewController {
    private let status = ShareStatus()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareStatusView(status: status) { [weak self] in self?.finish() })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await receive() }
    }

    private func receive() async {
        guard let inbox = ShareInbox.appGroup() else {
            status.phase = .failed("Repaso can't receive videos on this install.")
            return
        }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }
        guard !providers.isEmpty else {
            status.phase = .failed("There's no video to add.")
            return
        }
        var saved = 0
        for (n, provider) in providers.enumerated() {
            status.phase = .copying(index: n + 1, count: providers.count)
            if (try? await Self.deposit(provider, into: inbox)) != nil { saved += 1 }
        }
        guard saved > 0 else {
            status.phase = .failed("Couldn't add \(providers.count == 1 ? "this video" : "these videos").")
            return
        }
        if openApp(ShareInbox.openURL) {
            finish()
        } else {
            status.phase = .saved(saved)
        }
    }

    /// Copies one shared video into the inbox while the provider's temporary file still exists.
    private static func deposit(_ provider: NSItemProvider, into inbox: ShareInbox) async throws {
        let type = provider.registeredContentTypes.first { $0.conforms(to: .movie) } ?? .movie
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                guard let url else { return done.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                do {
                    try inbox.deposit(fileAt: url)
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    /// Extensions can't call `UIApplication.shared.open`, so this finds the app object up the responder chain.
    private func openApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication, app.responds(to: selector) {
                typealias Open = @convention(c) (NSObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                unsafeBitCast(app.method(for: selector), to: Open.self)(app, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

@Observable @MainActor
final class ShareStatus {
    enum Phase: Equatable {
        case copying(index: Int, count: Int)
        case saved(Int)
        case failed(String)
    }

    var phase: Phase = .copying(index: 1, count: 1)
}

private struct ShareStatusView: View {
    let status: ShareStatus
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch status.phase {
            case .copying(let index, let count):
                ProgressView().controlSize(.large)
                Text(count == 1 ? "Adding to Repaso…" : "Adding \(index) of \(count) to Repaso…")
                    .font(.headline)
                Text("Long videos take a moment.").font(.subheadline).foregroundStyle(.secondary)
            case .saved(let count):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text(count == 1 ? "Added to Repaso" : "\(count) videos added to Repaso").font(.headline)
                Text("Open Repaso to make clips.").font(.subheadline).foregroundStyle(.secondary)
                Button("Done", action: done).buttonStyle(.borderedProminent)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.orange)
                Text(message).font(.headline).multilineTextAlignment(.center)
                Button("Close", action: done).buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
    }
}
