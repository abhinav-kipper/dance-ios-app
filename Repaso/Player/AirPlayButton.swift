import SwiftUI
import AVKit

/// The system AirPlay route picker, white with a green "connected" state.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(Theme.accent)
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}
