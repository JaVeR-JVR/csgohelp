import AppKit
import CSGOHelperCore

/// Немадальное окно с инструкцией по разрешениям при первом запуске.
///
/// Панель намеренно не использует `runModal`: helper, запущенный через
/// LaunchAgent, должен продолжать обрабатывать SIGTERM и события workspace,
/// пока пользователь читает инструкцию.
final class PermissionGuidePanel: NSObject {
    private var panel: NSPanel?
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(status: PermissionStatus) {
        let panel = panel ?? makePanel()
        self.panel = panel
        titleLabel.stringValue = status.allRequired
            ? "Разрешения выданы"
            : "CSGO Helper нужны разрешения"
        detailsLabel.stringValue = Self.details(for: status)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "CSGO Helper — разрешения"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.center()

        let content = NSView()
        panel.contentView = content

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.font = .systemFont(ofSize: 12)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.maximumNumberOfLines = 0
        detailsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailsLabel.widthAnchor.constraint(equalToConstant: 480).isActive = true

        let accessibilityButton = NSButton(
            title: "Открыть Accessibility",
            target: self,
            action: #selector(openAccessibility)
        )
        let inputMonitoringButton = NSButton(
            title: "Открыть Input Monitoring",
            target: self,
            action: #selector(openInputMonitoring)
        )
        let laterButton = NSButton(title: "Позже", target: self, action: #selector(closePanel))
        accessibilityButton.bezelStyle = .rounded
        inputMonitoringButton.bezelStyle = .rounded
        laterButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [accessibilityButton, inputMonitoringButton, laterButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let stack = NSStackView(views: [titleLabel, detailsLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        return panel
    }

    private static func details(for status: PermissionStatus) -> String {
        var text = """
        Accessibility — отправка клавиш и мыши.
        Input Monitoring — перехват Shift+I, A/D и Space.

        Откройте оба раздела, включите CSGOHelper.app и перезапустите helper.
        TCC запоминает путь приложения: запускайте установленный .app, а не бинарник из .build.
        """
        if !status.allRequired {
            text += "\n\nТекущее состояние: \(status.summary)"
        }
        if status.secureInputEnabled {
            text += "\n\nSecure Input сейчас включён: клавиатурный перехват может не работать, "
                + "пока активно защищённое поле ввода."
        }
        return text
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openInputMonitoring() {
        Permissions.openInputMonitoringSettings()
    }

    @objc private func closePanel() {
        panel?.orderOut(nil)
    }
}
