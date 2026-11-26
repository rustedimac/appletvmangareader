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

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateDiagnostics()
    }

    override var contentOffset: CGPoint {
        didSet { updateDiagnostics() }
    }

    /// Exposed for UI tests: whether the strip has the remote, and where it is.
    private func updateDiagnostics() {
        accessibilityValue = "\(isFocused ? "focused" : "unfocused"); offset=\(Int(contentOffset.y.rounded())); viewport=\(Int(bounds.height))"
    }

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

    /// Moves focus to the strip, e.g. after the reader menu closes. Asks the
    /// window's root controller to re-run focus too, because a request from
    /// a view outside the focused branch is otherwise ignored.
    func requestFocus() {
        guard window != nil, !scrollView.isFocused else { return }
        UIFocusSystem.focusSystem(for: self)?.requestFocusUpdate(to: scrollView)
        setNeedsFocusUpdate()
        if let root = window?.rootViewController {
            root.setNeedsFocusUpdate()
            root.updateFocusIfNeeded()
        } else {
            updateFocusIfNeeded()
        }
    }
}

final class WebtoonPageView: UIView {
    var kind: WebtoonItemKind?
    var url: URL?
    var loadTask: Task<Void, Never>?
    /// The column width (device pixels) the shown image was decoded for.
    private(set) var shownWidth: Int?
    private var image: WebtoonPageImage?
    private var tileLayers: [CALayer] = []
    private let spinner = UIActivityIndicatorView(style: .large)
    private let failureView = WebtoonPageFailureView()
    /// The page didn't load; it shows why and how to retry.
    private(set) var isShowingFailure = false
    private var pageLabel = ""
    static let placeholderColor = UIColor(white: 0.5, alpha: 0.12)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isAccessibilityElement = true
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        failureView.isHidden = true
        addSubview(failureView)
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
        pageLabel = label
        accessibilityLabel = isShowingFailure ? "\(label) didn't load" : label
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
        accessibilityLabel = pageLabel
        accessibilityHint = nil
        isShowingFailure = false
        failureView.isHidden = true
        spinner.startAnimating()
    }

    /// The page couldn't be loaded even after automatic retries. The strip
    /// keeps its place; Select retries the failed pages on screen.
    func showFailure(_ message: String, pageNumber: Int) {
        if !isShowingFailure { showPlaceholder() }
        isShowingFailure = true
        spinner.stopAnimating()
        failureView.configure(title: "Page \(pageNumber) didn't load", message: message)
        failureView.isHidden = false
        accessibilityValue = "failed"
        accessibilityLabel = "\(pageLabel) didn't load"
        accessibilityHint = "Press Select to retry"
        setNeedsLayout()
    }

    func show(_ image: WebtoonPageImage) {
        self.image = image
        shownWidth = image.displayWidth
        isShowingFailure = false
        failureView.isHidden = true
        accessibilityLabel = pageLabel
        accessibilityHint = nil
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
        let size = failureView.sizeThatFits(CGSize(width: min(bounds.width - 40, 760), height: bounds.height))
        failureView.frame = CGRect(x: (bounds.width - size.width) / 2, y: max(0, min(bounds.midY, 360) - size.height / 2),
                                   width: size.width, height: size.height)
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

/// "Page 4 didn't load", the reason, and a Retry pill drawn as the
/// focused control: the strip holds focus, and Select retries.
final class WebtoonPageFailureView: UIView {
    private let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryLabel = PaddedLabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        messageLabel.font = .preferredFont(forTextStyle: .callout)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 2
        for label in [titleLabel, messageLabel] { label.textAlignment = .center }
        retryLabel.text = "Retry"
        retryLabel.font = .preferredFont(forTextStyle: .headline)
        retryLabel.textColor = .black
        retryLabel.backgroundColor = .white
        retryLabel.layer.cornerRadius = 12
        retryLabel.layer.masksToBounds = true
        retryLabel.textAlignment = .center
        let hint = UILabel()
        hint.text = "Press Select to retry"
        hint.font = .preferredFont(forTextStyle: .caption1)
        hint.textColor = .secondaryLabel
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        [icon, titleLabel, messageLabel, retryLabel, hint].forEach(stack.addArrangedSubview)
        addSubview(stack)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, message: String) {
        titleLabel.text = title
        messageLabel.text = message
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = stack.systemLayoutSizeFitting(CGSize(width: size.width, height: UIView.layoutFittingCompressedSize.height),
                                                   withHorizontalFittingPriority: .fittingSizeLevel,
                                                   verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: min(size.width, max(fitted.width, 300)), height: fitted.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = bounds
    }
}

/// A label with room around its text, for the Retry pill.
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 10, left: 36, bottom: 10, right: 36)

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
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
/// the longer it's held. Also runs auto-scroll and game controller stick
/// scrolling. Motion is timed by the clock, not by frame count, so a slow
/// frame never shortens a step, and the position is tracked below a pixel
/// so slow auto-scroll still moves smoothly.
@MainActor
final class WebtoonScrollDriver {
    weak var scrollView: UIScrollView?
    /// Largest offset in points.
    var maxOffset: () -> CGFloat = { 0 }
    var onMove: (() -> Void)?
    /// Whether the strip has nothing more to load below; auto-scroll stops
    /// at the bottom then, and otherwise waits there for the next chapter.
    var atEnd: () -> Bool = { true }
    /// Auto-scroll reached the end of the series and stopped.
    var onAutoScrollEnded: (() -> Void)?
    /// Auto-scroll speed level, or nil when auto-scroll is off.
    var autoLevel: Int? {
        didSet { if autoLevel != nil { start() } }
    }
    /// Game controller stick speed, in points per second (positive is down).
    var stickVelocity: CGFloat = 0 {
        didSet { if stickVelocity != 0 { start() } }
    }
    private(set) var target: CGFloat?
    /// The unrounded position; the scroll view gets it snapped to pixels.
    private var exactY: CGFloat = 0
    private var glideFrom: CGFloat = 0
    private var glideStart: CFTimeInterval = 0
    private var holdDirection: CGFloat = 0
    /// Momentum after a swipe, in points per second.
    private var flingVelocity: CGFloat = 0
    private var holdStart: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var link: CADisplayLink?
    /// How long a press must be held before it turns into continuous scrolling.
    let holdDelay: CFTimeInterval = 0.5
    /// How long one click's glide takes.
    let glideDuration: CFTimeInterval = 0.25

    private final class Proxy: NSObject {
        weak var driver: WebtoonScrollDriver?
        @objc func tick(_ link: CADisplayLink) { MainActor.assumeIsolated { driver?.tick() } }
    }

    var isActive: Bool { link != nil }

    /// Coasts after a swipe, slowing down like a scroll view does.
    func fling(velocity: CGFloat) {
        target = nil
        flingVelocity = velocity
        if abs(velocity) > 20 { start() }
    }

    func glide(to y: CGFloat) {
        guard let scrollView else { return }
        flingVelocity = 0
        target = min(max(0, y), maxOffset())
        glideFrom = scrollView.contentOffset.y
        glideStart = CACurrentMediaTime()
        start()
    }

    func beginHold(forward: Bool) {
        flingVelocity = 0
        holdDirection = forward ? 1 : -1
        holdStart = CACurrentMediaTime()
        start()
    }

    func endHold() {
        guard holdDirection != 0 else { return }
        let wasContinuous = CACurrentMediaTime() - holdStart >= holdDelay
        holdDirection = 0
        // A long hold stops where it is; a click keeps gliding to its target.
        if wasContinuous, target == nil { stopIfIdle() }
    }

    func stop() {
        target = nil
        flingVelocity = 0
        holdDirection = 0
        autoLevel = nil
        stickVelocity = 0
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
        guard link == nil else { return }
        lastTick = CACurrentMediaTime()
        exactY = scrollView?.contentOffset.y ?? 0
        let proxy = Proxy()
        proxy.driver = self
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopIfIdle() {
        if target == nil && holdDirection == 0 && flingVelocity == 0 && autoLevel == nil && stickVelocity == 0 {
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
        // Something else moved the strip (a swipe, a re-layout): follow it.
        if abs(exactY - scrollView.contentOffset.y) >= 1 / scale { exactY = scrollView.contentOffset.y }
        var y = exactY
        if holdDirection != 0, now - holdStart >= holdDelay {
            let speed = WebtoonScrolling.holdSpeed(heldFor: now - holdStart - holdDelay,
                                                   viewport: Double(scrollView.bounds.height))
            y += holdDirection * CGFloat(speed) * CGFloat(dt)
            // A hold never ends up short of the click's step it started with.
            if let t = target {
                let p = min(1, max(0, (now - glideStart) / glideDuration))
                let glideY = glideFrom + (t - glideFrom) * CGFloat(1 - pow(1 - p, 3))
                y = holdDirection > 0 ? max(y, glideY) : min(y, glideY)
                if p >= 1 { target = nil }
            }
        } else if let t = target {
            let p = min(1, max(0, (now - glideStart) / glideDuration))
            let eased = 1 - pow(1 - p, 3)
            y = glideFrom + (t - glideFrom) * CGFloat(eased)
            if p >= 1 {
                y = t
                target = nil
            }
        } else if flingVelocity != 0 {
            y += flingVelocity * CGFloat(dt)
            flingVelocity *= CGFloat(pow(0.998, dt * 1000))
            if abs(flingVelocity) < 10 || y <= 0 || y >= maxOffset() { flingVelocity = 0 }
        } else if stickVelocity != 0 || autoLevel != nil {
            y += stickVelocity * CGFloat(dt)
            if let level = autoLevel {
                let next = WebtoonAutoScroll.advance(offset: Double(min(y, maxOffset())), dt: dt, level: level,
                                                     viewport: Double(scrollView.bounds.height),
                                                     maxOffset: Double(maxOffset()), atEnd: atEnd())
                if let next {
                    y = CGFloat(next)
                } else {
                    autoLevel = nil
                    onAutoScrollEnded?()
                }
            }
        } else if holdDirection == 0 {
            stopIfIdle()
            return
        }
        y = min(max(0, y), maxOffset())
        exactY = y
        let snapped = (y * scale).rounded() / scale
        if snapped != scrollView.contentOffset.y {
            scrollView.contentOffset.y = snapped
        }
        onMove?()
        stopIfIdle()
    }
}
