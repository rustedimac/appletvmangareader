import SwiftUI
import MangaCore

/// What happens after four digits are entered.
enum PINPadFeedback {
    case accept
    /// Clears the dots and shows this message.
    case reject(String)
}

/// A four-digit PIN keypad driven with the Siri Remote: four dots, a 3×4
/// grid of digit buttons and delete. It submits as soon as the fourth digit
/// is in. Keys are `pin.key.<digit>` and `pin.delete`; the dots report how
/// many digits are in as their value (`pin.dots`).
struct PINPadView: View {
    let title: String
    var message: String? = nil
    let onComplete: (String) -> PINPadFeedback

    @State private var entry = PINEntry()
    @State private var error: String?
    @FocusState private var focusedKey: String?

    var body: some View {
        VStack(spacing: 44) {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pin.title")
                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)
                }
            }

            HStack(spacing: 30) {
                ForEach(0..<ProfilePIN.length, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.6), lineWidth: 3)
                        .background(Circle().fill(i < entry.digits.count ? Color.primary : Color.clear))
                        .frame(width: 34, height: 34)
                }
            }
            .accessibilityElement()
            .accessibilityIdentifier("pin.dots")
            .accessibilityLabel("PIN")
            .accessibilityValue("\(entry.digits.count)")

            Text(error ?? " ")
                .foregroundStyle(.red)
                .accessibilityIdentifier("pin.message")
                .opacity(error == nil ? 0 : 1)

            Grid(horizontalSpacing: 28, verticalSpacing: 28) {
                GridRow { key(1); key(2); key(3) }
                GridRow { key(4); key(5); key(6) }
                GridRow { key(7); key(8); key(9) }
                GridRow {
                    Color.clear.frame(width: 140, height: 100)
                    key(0)
                    Button {
                        entry.deleteLast()
                    } label: {
                        Image(systemName: "delete.left").font(.title2).frame(width: 140, height: 100)
                    }
                    .accessibilityIdentifier("pin.delete")
                    .accessibilityLabel("Delete")
                    .focused($focusedKey, equals: "delete")
                }
            }
            .focusSection()
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusedKey = "1" }
    }

    private func key(_ digit: Int) -> some View {
        Button {
            press(digit)
        } label: {
            Text("\(digit)")
                .font(.title.monospacedDigit())
                .frame(width: 140, height: 100)
        }
        .accessibilityIdentifier("pin.key.\(digit)")
        .focused($focusedKey, equals: "\(digit)")
    }

    private func press(_ digit: Int) {
        error = nil
        entry.append(digit)
        guard entry.isComplete else { return }
        let pin = entry.digits
        entry.clear()
        if case .reject(let message) = onComplete(pin) {
            error = message
        }
    }
}

/// Shows `content` once the PIN for `kind` is entered (or right away when
/// there's no PIN or it was entered earlier this session).
struct PINGate<Content: View>: View {
    enum Kind: Equatable {
        /// This profile's PIN.
        case profile(UUID)
        /// Any profile's PIN, when any profile has one (adding a profile).
        case anyProtected
    }

    @Environment(AppModel.self) private var model
    let kind: Kind
    var reason: String = "Enter the PIN to continue."
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isUnlocked {
            content()
        } else {
            PINPadView(title: title, message: reason) { pin in
                PINGate.feedback(model.attemptPIN(pin, candidates: candidates))
            }
        }
    }

    private var candidates: [UUID] {
        switch kind {
        case .profile(let id): return [id]
        case .anyProtected: return model.protectedProfiles
        }
    }

    private var isUnlocked: Bool {
        switch kind {
        case .profile(let id): return !model.isLocked(id)
        case .anyProtected:
            let protected = model.protectedProfiles
            return protected.isEmpty || protected.contains { !model.isLocked($0) }
        }
    }

    private var title: String {
        switch kind {
        case .profile(let id):
            let name = model.state.profiles.first { $0.id == id }?.name ?? "Profile"
            return "Enter \(name)'s PIN"
        case .anyProtected:
            return "Enter a profile PIN"
        }
    }

    static func feedback(_ result: ProfileLocks.Result) -> PINPadFeedback {
        switch result {
        case .unlocked: return .accept
        case .wrong(let left):
            return .reject(left > 0 && left <= 3 ? "Wrong PIN. \(left) \(left == 1 ? "try" : "tries") left." : "Wrong PIN.")
        case .lockedOut(let seconds):
            return .reject("Too many tries. Wait \(PINGate.duration(seconds)).")
        }
    }

    static func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) seconds" : "\((seconds + 59) / 60) minutes"
    }
}

/// Choosing a new PIN: enter it, then enter it again.
struct PINSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let profileName: String
    let onSet: (String) -> Void

    @State private var first: String?
    @State private var notice: String?

    var body: some View {
        Group {
            if let first {
                PINPadView(title: "Enter it again", message: "Confirm the new PIN for \(profileName).") { pin in
                    guard pin == first else {
                        notice = "The PINs didn't match. Choose a PIN again."
                        self.first = nil
                        return .accept
                    }
                    onSet(pin)
                    dismiss()
                    return .accept
                }
                .id("confirm")
            } else {
                PINPadView(title: "Choose a PIN for \(profileName)",
                           message: notice ?? "Four digits. You'll need it to change this profile's content settings.") { pin in
                    notice = nil
                    first = pin
                    return .accept
                }
                .id("choose")
            }
        }
    }
}
