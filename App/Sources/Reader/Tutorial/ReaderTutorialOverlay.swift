import SwiftUI
import MangaCore

/// The tutorial's caption card, bottom left so it stays clear of the
/// reader options drawer on the right: which step this is, the input with
/// its symbol, and what to do. It moves on by itself when the reader
/// reports the step's goal (`ReaderSession.note(_:)`). It never takes focus,
/// so every button reaches the reader as usual. The last step also credits
/// the sample.
struct ReaderTutorialOverlay: View {
    let session: ReaderSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let progress = session.tutorial, let step = progress.current, session.loadState == .loaded {
                card(step, of: progress.steps.count)
                    .id(step.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.leading, Space.xxl)
        .padding(.bottom, 140)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(.easeInOut(duration: 0.3), value: session.tutorial?.index)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func card(_ step: ReaderTutorial.Step, of count: Int) -> some View {
        let finished = step.goal == .finish
        return HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: step.symbol)
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 80)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(finished ? "Controls Tutorial" : "Step \(step.id + 1) of \(count - 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(step.input)
                    .font(.headline)
                Text(step.caption)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if finished {
                    Text(ReaderTutorial.sampleCredit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reader.tutorial.credit")
                } else {
                    Text("Press Menu with nothing open to leave the tutorial.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: 820, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reader.tutorial.step")
        .accessibilityValue(step.goal.rawValue)
    }
}
