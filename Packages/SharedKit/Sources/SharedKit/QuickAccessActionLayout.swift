public enum QuickAccessActionKind: String, CaseIterable, Sendable {
    case drag
    case copy
    case save
    case systemShare
    case upload
    case annotate
    case findSensitive
    case ocr
    case pin
}

public enum QuickAccessActionLayout {
    public static func visibleActions(sharingAvailable: Bool) -> [QuickAccessActionKind] {
        var actions: [QuickAccessActionKind] = [.drag, .copy, .save, .systemShare]
        if sharingAvailable {
            actions.append(.upload)
        }
        actions.append(contentsOf: [.annotate, .findSensitive])
        return actions
    }

    public static let overflowActions: [QuickAccessActionKind] = [.pin, .ocr]
}
