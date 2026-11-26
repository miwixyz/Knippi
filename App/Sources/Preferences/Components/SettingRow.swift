import SwiftUI

struct SettingRow<Control: View>: View {
    let label: LocalizedStringKey
    var sublabel: LocalizedStringKey? = nil
    var showDivider: Bool = false
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            if showDivider {
                Divider()
                    .background(Color.white.opacity(0.06))
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(FamilyTheme.font(13))
                        .foregroundStyle(.primary)
                    if let sublabel {
                        Text(sublabel)
                            .font(FamilyTheme.font(11))
                            .foregroundStyle(FamilyTheme.textSecondary)
                    }
                }
                Spacer()
                // Most controls here are `Toggle("")`/`Picker("")` without a label of
                // their own: the group carries the row's name, so VoiceOver reads
                // "Automatically Check for Updates, switch" instead of just "switch".
                control
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text(label))
                    .accessibilityHint(sublabel.map { Text($0) } ?? Text(verbatim: ""))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 40)
        }
    }
}
