import SwiftUI
import MangaCore

/// The page scrubber: a strip of page thumbnails along the bottom of the
/// screen with a progress bar, over the page. Opened with Pages in the
/// reader menu, in both the paged and the vertical reader.
///
/// Siri Remote: left/right moves one page (in reading direction, so for
/// right-to-left manga page 1 is on the right and pressing left moves
/// forward), up jumps 10 pages back and down 10 pages forward, click opens
/// the page, Menu or Play/Pause closes the scrubber.
///
/// Thumbnails come from the same image pipeline as the pages, decoded
/// small, and only for the part of the strip that's on screen.
struct PageScrubberView: View {
    let session: ReaderSession

    @Environment(\.imagePipeline) private var pipeline
    @Environment(\.displayScale) private var displayScale
    @FocusState private var focusedPage: Int?
    /// The page the progress bar and label follow (the focused one).
    @State private var shownPage: Int = 0

    static let thumbnailHeight: CGFloat = 240

    private var direction: ReadingDirection { session.settings.direction }
    private var pageCount: Int { session.pageCount }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            panel
                .frame(maxWidth: .infinity)
                .background(.thickMaterial)
        }
        .ignoresSafeArea()
        .focusSection()
        .onPlayPauseCommand { session.isMenuPresented = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.scrubber")
    }

    private var panel: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                    Text(PageScrubber.label(page: shownPage, pageCount: pageCount))
                        .font(.headline)
                        .monospacedDigit()
                        .accessibilityIdentifier("reader.scrubber.label")
                    Text(session.chapter.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: Space.l)
                    Text("Up or down: 10 pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrubberProgressBar(progress: PageScrubber.progress(page: shownPage, pageCount: pageCount),
                                    rightToLeft: direction == .rightToLeft)
                    .accessibilityElement()
                    .accessibilityLabel("Chapter progress")
                    .accessibilityValue(PageScrubber.label(page: shownPage, pageCount: pageCount))
                    .accessibilityIdentifier("reader.scrubber.progress")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Space.l) {
                        ForEach(PageScrubber.screenOrder(pageCount: pageCount, direction: direction), id: \.self) { page in
                            thumbnail(page, proxy: proxy)
                                .id(page)
                        }
                    }
                    // Room for the focused thumbnail to lift.
                    .padding(.vertical, Space.m)
                    .padding(.horizontal, Layout.safeSide)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -Layout.safeSide)
            }
            .padding(.top, Space.l)
            .padding(.bottom, Layout.safeBottom)
            .padding(.horizontal, Layout.safeSide)
            .onAppear {
                let current = min(max(0, session.currentPage), max(0, pageCount - 1))
                shownPage = current
                proxy.scrollTo(current, anchor: .center)
                focus(current, proxy: proxy)
            }
            .onChange(of: focusedPage) { _, page in
                if let page { shownPage = page }
            }
        }
    }

    private func thumbnail(_ page: Int, proxy: ScrollViewProxy) -> some View {
        let isCurrent = session.visiblePages.contains(page)
        let width = PageScrubber.thumbnailWidth(height: Double(Self.thumbnailHeight), size: session.size(ofPage: page))
        return VStack(spacing: Space.xs) {
            Button {
                session.jump(toPage: page)
            } label: {
                ScrubberThumbnail(session: session, page: page, pipeline: pipeline,
                                  targetSize: CGSize(width: width * displayScale,
                                                     height: Self.thumbnailHeight * displayScale))
                    .frame(width: width, height: Self.thumbnailHeight)
            }
            .buttonStyle(.card)
            .focused($focusedPage, equals: page)
            .onMoveCommand { move($0, proxy: proxy) }
            .accessibilityLabel("Page \(page + 1)")
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityIdentifier("reader.scrubber.page.\(page)")
            Text(isCurrent ? "\(page + 1) · Now" : "\(page + 1)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }

    /// Up and down jump 10 pages. Left and right are the focus engine's.
    private func move(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard let from = focusedPage else { return }
        let forward: Bool
        switch direction {
        case .down: forward = true
        case .up: forward = false
        default: return
        }
        let target = PageScrubber.jump(from: from, forward: forward, pageCount: pageCount)
        guard target != from else { return }
        shownPage = target
        withAnimation { proxy.scrollTo(target, anchor: .center) }
        focus(target, proxy: proxy)
    }

    /// The strip is lazy, so a thumbnail far away may not exist yet: scroll
    /// it in, then focus it on the next turns of the run loop (focus set in
    /// the same pass a view appears is dropped on tvOS).
    private func focus(_ page: Int, proxy: ScrollViewProxy) {
        for delay in [0.05, 0.25, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard focusedPage != page, shownPage == page else { return }
                proxy.scrollTo(page, anchor: .center)
                focusedPage = page
            }
        }
    }
}

/// A thin bar showing how far through the chapter the focused page is. For
/// right-to-left books it fills from the right, matching the thumbnails.
private struct ScrubberProgressBar: View {
    let progress: Double
    let rightToLeft: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: rightToLeft ? .trailing : .leading) {
                Capsule().fill(.secondary.opacity(0.35))
                Capsule().fill(.primary)
                    .frame(width: max(8, geo.size.width * progress))
            }
        }
        .frame(height: 8)
    }
}

/// One page thumbnail, loaded small from the shared pipeline.
private struct ScrubberThumbnail: View {
    let session: ReaderSession
    let page: Int
    let pipeline: any ImageLoading
    let targetSize: CGSize

    @State private var image: LoadedImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            if let image {
                Image(uiImage: image.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("\(page + 1)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .pictureAdjustments(session.settings.picture)
        .task(id: session.page(page)?.url) { await load() }
    }

    private func load() async {
        guard let url = session.page(page)?.url else { return }
        if let hit = pipeline.cachedImage(for: url, targetSize: targetSize, scaling: .fit) {
            image = hit
            return
        }
        guard let loaded = try? await pipeline.load(url, server: session.server, targetSize: targetSize,
                                                    scaling: .fit) else { return }
        image = loaded
        session.reportSize(loaded.pixelSize, forPage: page)
    }
}
