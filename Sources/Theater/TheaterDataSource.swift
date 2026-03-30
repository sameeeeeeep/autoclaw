import Foundation
import Combine

/// Protocol that the main app's TranscribeService conforms to, providing
/// the data TheaterPIPView needs without a direct dependency.
@MainActor
public protocol TheaterDataSource: ObservableObject {
    var sessionDialog: [DialogLine] { get }
    var dialogVoice: DialogVoiceService { get }
    var isGeneratingPrompt: Bool { get }
}
