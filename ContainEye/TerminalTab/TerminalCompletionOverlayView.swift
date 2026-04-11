import UIKit

// MARK: - Overlay Container

final class TerminalCompletionOverlayView: UIView {
    static let itemHeight = UIFloat(34)
    static let preferredWidth = UIFloat(260)

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private var rowViews: [TerminalCompletionRowView] = []
    private(set) var selectedIndex: Int = 0
    var onSelectionChanged: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = UIFloat(12)
        layer.shadowOffset = CGSize(width: 0, height: UIFloat(3))

        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = UIFloat(10)
        blurView.layer.cornerCurve = .continuous
        addSubview(blurView)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func preferredHeight(for count: Int) -> CGFloat {
        CGFloat(max(0, count)) * itemHeight
    }

    func update(
        suggestions: [CommandSuggestion],
        typedInput: String,
        selectedIndex: Int,
        onSelect: @escaping (CommandSuggestion) -> Void
    ) {
        self.selectedIndex = selectedIndex

        for row in rowViews { row.removeFromSuperview() }
        rowViews.removeAll(keepingCapacity: false)

        for (index, suggestion) in suggestions.enumerated() {
            let row = TerminalCompletionRowView()
            row.configure(
                suggestion: suggestion,
                typedInput: typedInput,
                isSelected: index == selectedIndex,
                showSeparator: index < suggestions.count - 1
            )
            row.addAction(UIAction { _ in onSelect(suggestion) }, for: .touchUpInside)
            blurView.contentView.addSubview(row)
            rowViews.append(row)
        }

        setNeedsLayout()
    }

    func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        let newIndex = max(0, min(count - 1, selectedIndex + delta))
        guard newIndex != selectedIndex else { return }
        selectedIndex = newIndex
        for (i, row) in rowViews.enumerated() {
            row.setSelected(i == selectedIndex)
        }
        onSelectionChanged?(selectedIndex)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        let h = TerminalCompletionOverlayView.itemHeight
        for (i, row) in rowViews.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h)
        }
    }
}

// MARK: - Row View

private final class TerminalCompletionRowView: UIControl {
    private let iconView = UIImageView()
    private let textLabel = UILabel()
    private let hintLabel = UILabel()
    private let separator = UIView()
    private let selectionBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        selectionBackground.backgroundColor = UIColor.tintColor.withAlphaComponent(0.15)
        selectionBackground.isUserInteractionEnabled = false
        addSubview(selectionBackground)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .secondaryLabel
        addSubview(iconView)

        textLabel.font = UIFont.monospacedSystemFont(ofSize: UIFloat(13), weight: .regular)
        textLabel.textColor = .label
        textLabel.lineBreakMode = .byTruncatingTail
        addSubview(textLabel)

        hintLabel.font = UIFont.systemFont(ofSize: UIFloat(11), weight: .medium)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.text = "tab"
        addSubview(hintLabel)

        separator.backgroundColor = UIColor.separator.withAlphaComponent(0.4)
        addSubview(separator)

        addTarget(self, action: #selector(touchHighlight), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUnhighlight), for: [.touchUpInside, .touchDragExit, .touchCancel, .touchUpOutside])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        suggestion: CommandSuggestion,
        typedInput: String,
        isSelected: Bool,
        showSeparator: Bool
    ) {
        let iconName: String
        switch suggestion.source {
        case .snippet: iconName = "ellipsis.curlybraces"
        case .history: iconName = "clock"
        case .documentTree, .live: iconName = "folder"
        }
        iconView.image = UIImage(systemName: iconName)
        textLabel.text = completionText(for: suggestion.text, typedInput: typedInput)
        hintLabel.isHidden = !isSelected
        separator.isHidden = !showSeparator
        selectionBackground.isHidden = !isSelected
    }

    func setSelected(_ selected: Bool) {
        selectionBackground.isHidden = !selected
        hintLabel.isHidden = !selected
    }

    private func completionText(for suggestion: String, typedInput: String) -> String {
        let trimmed = typedInput.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return suggestion }

        // Strip only fully-typed words from the suggestion so the current
        // (partially-typed) word is always shown in full.
        // e.g. typed "docker p", suggestion "docker ps" → display "ps"
        let inputWords = trimmed.components(separatedBy: " ")
        let suggestionWords = suggestion.components(separatedBy: " ")

        // Count leading words that match exactly (case-insensitive).
        var matchedWords = 0
        for (typed, suggested) in zip(inputWords, suggestionWords) {
            if typed.lowercased() == suggested.lowercased() {
                matchedWords += 1
            } else {
                break
            }
        }

        guard matchedWords > 0 else { return suggestion }

        let remaining = suggestionWords.dropFirst(matchedWords).joined(separator: " ")
        return remaining.isEmpty ? suggestion : remaining
    }

    @objc private func touchHighlight() {
        selectionBackground.backgroundColor = UIColor.tintColor.withAlphaComponent(0.22)
    }

    @objc private func touchUnhighlight() {
        selectionBackground.backgroundColor = UIColor.tintColor.withAlphaComponent(0.15)
        if selectionBackground.isHidden {
            selectionBackground.backgroundColor = UIColor.tintColor.withAlphaComponent(0.15)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        selectionBackground.frame = bounds

        let pad = UIFloat(10)
        let iconSize = UIFloat(13)
        iconView.frame = CGRect(x: pad, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

        hintLabel.sizeToFit()
        let hintW = hintLabel.frame.width
        let hintX = bounds.width - hintW - pad
        hintLabel.frame = CGRect(
            x: hintX,
            y: (bounds.height - hintLabel.frame.height) / 2,
            width: hintW,
            height: hintLabel.frame.height
        )

        let textX = iconView.frame.maxX + UIFloat(8)
        let textRight = hintLabel.isHidden ? (bounds.width - pad) : (hintX - UIFloat(6))
        textLabel.frame = CGRect(x: textX, y: 0, width: max(0, textRight - textX), height: bounds.height)

        separator.frame = CGRect(x: pad, y: bounds.height - 0.5, width: max(0, bounds.width - 2 * pad), height: 0.5)
    }
}
