import SwiftUI

struct SettingsPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    model.showingSettings = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 44, height: 1)
            }

            ScrollView {
                VStack(spacing: 12) {
                    generalSection
                    historySection
                    appearanceSection
                    privacySection
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "General") {
            settingButtonRow(title: "Launch at Login", value: boolLabel(model.settings.launchAtLogin)) {
                model.setLaunchAtLogin(!model.settings.launchAtLogin)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Global Shortcut")
                    .foregroundStyle(.secondary)
                HotkeyRecorderView(shortcut: model.settings.globalShortcut, onChange: model.updateGlobalShortcut)
                    .frame(height: 30)
            }

            settingButtonRow(title: "Paste on click", value: boolLabel(model.settings.pasteOnClick)) {
                model.setPasteOnClick(!model.settings.pasteOnClick)
            }

            settingButtonRow(title: "Show source app icons", value: boolLabel(model.settings.showSourceAppIcons)) {
                model.setShowSourceIcons(!model.settings.showSourceAppIcons)
            }

            settingButtonRow(title: "Compact mode", value: boolLabel(model.settings.compactMode)) {
                model.setCompactMode(!model.settings.compactMode)
            }

            if let error = model.launchAtLoginError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var historySection: some View {
        SettingsSection(title: "History") {
            menuRow(title: "History limit", value: model.settings.historyLimit.displayName) {
                ForEach(HistoryLimit.allCases, id: \.self) { limit in
                    Button(limit.displayName) {
                        model.setHistoryLimit(limit)
                    }
                }
            }

            menuRow(title: "Auto-clear after", value: model.settings.autoClearAfter.displayName) {
                ForEach(AutoClearIntervalSetting.allCases, id: \.self) { interval in
                    Button(interval.displayName) {
                        model.setAutoClear(interval)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Exclude apps")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add App…") {
                        model.addExcludedApp()
                    }
                    .buttonStyle(.plain)
                }

                if model.settings.excludedApps.isEmpty {
                    Text("No excluded apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.settings.excludedApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: model.sourceIcon(for: app))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(app.displayName)
                            Spacer()
                            Button {
                                model.removeExcludedApp(app)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance") {
            settingButtonRow(title: "Follow system appearance", value: boolLabel(model.settings.followSystemAppearance)) {
                model.setFollowSystemAppearance(!model.settings.followSystemAppearance)
            }

            if !model.settings.followSystemAppearance {
                HStack(spacing: 8) {
                    appearanceButton(title: "Light", appearance: .light)
                    appearanceButton(title: "Dark", appearance: .dark)
                    Spacer()
                }
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            settingButtonRow(title: "Pause capturing", value: boolLabel(model.settings.pauseCapturing)) {
                model.setPauseCapturing(!model.settings.pauseCapturing)
            }

            HStack {
                Text("Accessibility")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.permissionState.accessibilityGranted ? "Granted" : "Not granted")
                    .foregroundStyle(model.permissionState.accessibilityGranted ? .green : .secondary)
            }

            Button("Clear all data") {
                model.clearAllData()
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button("Quit ClipStack") {
                model.quitApplication()
            }
            .buttonStyle(.bordered)
        }
    }

    private func appearanceButton(title: String, appearance: ForcedAppearance) -> some View {
        Button(title) {
            model.setForcedAppearance(appearance)
        }
        .buttonStyle(.bordered)
        .tint(model.settings.forcedAppearance == appearance ? .accentColor : .gray)
    }

    private func boolLabel(_ value: Bool) -> String {
        value ? "On" : "Off"
    }

    private func settingButtonRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(value, action: action)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func menuRow<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            Menu(value) {
                content()
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
