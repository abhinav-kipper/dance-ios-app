import PhotosUI

extension PHPickerFilter {
    /// Every kind of video, so the picker also lists the Screen Recordings, Slo-mo and Cinematic albums
    /// (plain `.videos` leaves those collections out).
    static let importableVideos = PHPickerFilter.any(of: [.videos, .screenRecordings, .slomoVideos, .cinematicVideos])
}
