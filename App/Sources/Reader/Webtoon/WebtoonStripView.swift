import UIKit
import MangaCore

/// The scroll view behind the webtoon reader. It takes focus so it gets the
/// Siri Remote: swipes on the touch surface pan it (indirect touches), and
/// clicks are handed to `onPress`. Presses it doesn't handle (Menu) go up
/// the responder chain, so SwiftUI's exit command still closes the reader.
final class WebtoonScrollView: UIScrollView {
    /// Return true if the press was handled. `began` is false on release.
    var onPress: ((UIPress.PressType, _ began: Bool) -> Bool)?

    override var canBecomeFocused: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { !(onPress?($0.type, true) ?? false) }
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { !(onPress?($0.type, false) ?? false) }
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.filter { !(onPress?($0.type, false) ?? false) }
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }
}

/// Holds the scroll view and tells the controller when its size changes.
final class WebtoonContainerView: UIView {
    let scrollView = WebtoonScrollView()
    var onLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(scrollView)
        backgroundColor = .clear
        accessibilityIdentifier = "reader.webtoon"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [scrollView] }

    override func layoutSubviews() {
        super.layoutSubviews()
        if scrollView.frame != bounds { scrollView.frame = bounds }
        onLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { requestFocus() }
    }

    /// Moves focus to the strip, e.g. after the reader menu closes.
    func requestFocus() {
        guard window != nil, !scrollView.isFocused else { return }
        if let system = UIFocusSystem.focusSystem(for: self) {
            system.requestFocusUpdate(to: scrollView)
            system.updateFocusIfNeeded()
        } else {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }
}

/// One page in the strip: a placeholder until the image arrives, then the
/// image as one or more tile layers stacked edge to edge.
final class WebtoonPageView: UIView {
    var kind: WebtoonItemKind?
    var url: URL?
    var loadTask: Task<Void, Never>?
    /// The column width (device pixels) the shown image was decoded for.
    private(set) var shownWidth: Int?
    private var image: WebtoonPageImage?
    private var tileLayers: [CALayer] = []
    private let spinner = UIActivityIndicatorView(style: .large)
    static let placeholderColor = UIColor(white: 0.5, alpha: 0.12)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isAccessibilityElement = true
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        showPlaceholder()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func prepare(kind: WebtoonItemKind, url: URL?, label: String, identifier: String) {
        if self.kind != kind || self.url != url {
            loadTask?.cancel()
            loadTask = nil
            showPlaceholder()
        }
        self.kind = kind
        self.url = url
        accessibilityLabel = label
        accessibilityIdentifier = identifier
    }

    func recycle() {
        loadTask?.cancel()
        loadTask = nil
        kind = nil
        url = nil
        showPlaceholder()
    }

    func showPlaceholder() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tileLayers.forEach { $0.removeFromSuperlayer() }
        tileLayers = []
        CATransaction.commit()
        image = nil
        shownWidth = nil
        backgroundColor = Self.placeholderColor
        accessibilityValue = "loading"
        spinner.startAnimating()
    }

    func show(_ image: WebtoonPageImage) {
        self.image = image
        shownWidth = image.displayWidth
        spinner.stopAnimating()
        backgroundColor = .clear
        accessibilityValue = "loaded"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tileLayers.forEach { $0.removeFromSuperlayer() }
        tileLayers = image.tiles.map { tile in
            let layer = CALayer()
            layer.contents = tile
            layer.contentsGravity = .resize
            layer.magnificationFilter = .linear
            layer.minificationFilter = .linear
            layer.allowsEdgeAntialiasing = false
            self.layer.addSublayer(layer)
            return layer
        }
        layoutTiles()
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: min(bounds.midY, 300))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutTiles()
        CATransaction.commit()
    }

    /// Places tiles at whole device pixels. If the page is shown at another
    /// size than it was decoded for (the width setting just changed), the
    /// tiles stretch to fill until the new decode arrives.
    private func layoutTiles() {
        guard let image, !tileLayers.isEmpty else { return }
        let total = CGFloat(max(1, image.displayHeight))
        let scale = max(1, window?.screen.scale ?? traitCollection.displayScale)
        for (layer, tile) in zip(tileLayers, image.plan.tiles) {
            let y = (bounds.height * CGFloat(tile.displayY) / total * scale).rounded() / scale
            let maxY = (bounds.height * CGFloat(tile.displayY + tile.displayHeight) / total * scale).rounded() / scale
            layer.frame = CGRect(x: 0, y: y, width: bounds.width, height: maxY - y)
        }
    }
}

/// Divider between two chapters, Mihon style: what you finished and what's next.
final class WebtoonBreakView: UIView {
    private let finishedLabel = UILabel()
    private let nextLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        finishedLabel.font = .preferredFont(forTextStyle: .callout)
        finishedLabel.textColor = .secondaryLabel
        nextLabel.font = .preferredFont(forTextStyle: .title3)
        nextLabel.textColor = .label
        for label in [finishedLabel, nextLabel] {
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            finishedLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            finishedLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            nextLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nextLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 6),
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "reader.webtoon.break"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(finished finishedTitle: String?, next nextTitle: String) {
        finishedLabel.text = finishedTitle.map { "Finished \($0)" }
        nextLabel.text = "Next: \(nextTitle)"
        accessibilityLabel = nextTitle
    }
}

/// Footer after the series' last chapter.
final class WebtoonEndView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.text = "No more chapters"
        label.font = .preferredFont(forTextStyle: .title3)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "reader.webtoon.end"
        accessibilityLabel = "No more chapters"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Smooth remote-driven scrolling: clicks glide to a target (presses in a
/// row add up), and holding a direction scrolls continuously, speeding up
/// the longer it's held. Motion is timed by the clock, not by frame count,
/// so a slow frame never shortens a step.
@MainActor
final class WebtoonScrollDriver {
    weak var scrollView: UIScrollView?
    /// Largest offset in points.
    var maxOffset: () -> CGFloat = { 0 }
    var onMove: (() -> Void)?
    private(set) var target: CGFloat?
    private var glideFrom: CGFloat = 0
    private var glideStart: CFTimeInterval = 0
    private var holdDirection: CGFloat = 0
    private var holdStart: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var link: CADisplayLink?
    /// How long a press must be held before it turns into continuous scrolling.
    let holdDelay: CFTimeInterval = 0.35
    /// How long one click's glide takes.
    let glideDuration: CFTimeInterval = 0.25

    private final class Proxy: NSObject {
        weak var driver: WebtoonScrollDriver?
        @objc func tick(_ link: CADisplayLink) { MainActor.assumeIsolated { driver?.tick() } }
    }

    var isActive: Bool { link != nil }

    func glide(to y: CGFloat) {
        guard let scrollView else { return }
        target = min(max(0, y), maxOffset())
        glideFrom = scrollView.contentOffset.y
        glideStart = CACurrentMediaTime()
        start()
    }

    func beginHold(forward: Bool) {
        holdDirection = forward ? 1 : -1
        holdStart = CACurrentMediaTime()
        start()
    }

    func endHold() {
        guard holdDirection != 0 else { return }
        let wasContinuous = CACurrentMediaTime() - holdStart >= holdDelay
        holdDirection = 0
        // A long hold stops where it is; a click keeps gliding to its target.
        if wasContinuous { target = nil; stopIfIdle() }
    }

    func stop() {
        target = nil
        holdDirection = 0
        link?.invalidate()
        link = nil
    }

    /// Content above moved by `delta` points; keep the glide in step.
    func shift(by delta: CGFloat) {
        guard delta != 0, let t = target else { return }
        target = t + delta
        glideFrom += delta
    }

    private func start() {
        lastTick = CACurrentMediaTime()
        guard link == nil else { return }
        let proxy = Proxy()
        proxy.driver = self
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopIfIdle() {
        if target == nil && holdDirection == 0 {
            link?.invalidate()
            link = nil
        }
    }

    private func tick() {
        guard let scrollView else { stop(); return }
        let now = CACurrentMediaTime()
        let dt = min(0.25, max(0, now - lastTick))
        lastTick = now
        let scale = max(1, scrollView.traitCollection.displayScale)
        var y = scrollView.contentOffset.y
        if holdDirection != 0, now - holdStart >= holdDelay {
            target = nil
            let speed = WebtoonScrolling.holdSpeed(heldFor: now - holdStart - holdDelay,
                                                   viewport: Double(scrollView.bounds.height))
            y += holdDirection * CGFloat(speed) * CGFloat(dt)
        } else if let t = target {
            let p = min(1, max(0, (now - glideStart) / glideDuration))
            let eased = 1 - pow(1 - p, 3)
            y = glideFrom + (t - glideFrom) * CGFloat(eased)
            if p >= 1 {
                y = t
                target = nil
            }
        } else if holdDirection == 0 {
            stopIfIdle()
            return
        }
        y = min(max(0, y), maxOffset())
        y = (y * scale).rounded() / scale
        if y != scrollView.contentOffset.y {
            scrollView.contentOffset.y = y
        }
        onMove?()
        stopIfIdle()
    }
}
