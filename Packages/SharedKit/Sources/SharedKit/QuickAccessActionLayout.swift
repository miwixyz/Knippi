public enum QuickAccessActionKind: String, CaseIterable, Sendable {
    case drag
    case copy
    case save
    case upload
    case annotate
    case findSensitive
    case ocr
    case pin
}

public enum QuickAccessActionLayout {
    public static func visibleActions(sharingAvailable: Bool) -> [QuickAccessActionKind] {
        var actions: [QuickAccessActionKind] = [.drag, .copy, .save]
        if sharingAvailable {
            actions.append(.upload)
        }
        actions.append(contentsOf: [.annotate, .findSensitive, .pin])
        return actions
    }

    public static let overflowActions: [QuickAccessActionKind] = [.ocr]
}
