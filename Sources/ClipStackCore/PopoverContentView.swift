import SwiftUI

public struct PopoverContentView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    public init() {}

    public var body: some View {
        VisualEffectView()
            .overlay {
                Group {
                    if model.showingSettings {
                        SettingsPanelView()
                    } else {
                        MainPanelView(searchFocused: $searchFocused)
                    }
                }
                .padding(12)
                .frame(width: 340, height: 520)
            }
            .background(EscapeKeyMonitor {
                model.onRequestPopoverClose?()
            })
            .preferredColorScheme(model.preferredColorScheme)
            .onChange(of: model.popoverOpenToken) { _ in
                DispatchQueue.main.async {
                    searchFocused = true
                }
            }
    }
}
