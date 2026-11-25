import AVFoundation

/// The app makes no sound, so it uses the ambient audio category: music
/// or a podcast the user started in another app keeps playing while they
/// read, instead of stopping when the app opens.
enum AudioSessionSetup {
    static func configure(_ session: AVAudioSession = .sharedInstance()) {
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } catch {
            // Not fatal: the system default only means other audio may pause.
        }
    }
}
