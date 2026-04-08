import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainPanelView: View {
    @EnvironmentObject private var model: AppModel
    let searchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search clips…", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .focused(searchFocused)

            Picker("", selection: $model.selectedFilter) {
                ForEach(ClipFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if !model.pinnedClips.isEmpty {
                        SectionHeader(title: "Pinned")
                        ForEach(model.pinnedClips) { clip in
                            ClipRowView(clip: clip)
                                .onDrag {
                                    model.draggedPinnedClipID = clip.id
                                    return NSItemProvider(object: clip.id.uuidString as NSString)
                                }
                                .onDrop(of: [UTType.text], delegate: PinnedClipDropDelegate(targetID: clip.id, model: model))
                        }

                        Divider()
                            .padding(.vertical, 4)
                    }

                    if model.historyItems.isEmpty {
                        EmptyStateView()
                    } else {
                        ForEach(model.historyItems) { item in
                            clipItemView(item)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Button("Clear History") {
                    model.clearHistory()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 28)
        }
    }

    @ViewBuilder
    private func clipItemView(_ item: ClipListItem) -> some View {
        switch item {
        case let .clip(clip):
            ClipRowView(clip: clip)
        case let .group(group):
            GroupRowView(group: group)
        }
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No clips yet")
                .font(.headline)
            Text("Copy text, images, files, or URLs and ClipStack will keep them here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }
}

private struct GroupRowView: View {
    @EnvironmentObject private var model: AppModel

    let group: ClipGroup
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.sourceIcon(forKey: group.sourceIconKey))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(group.clips.count) clips from \(group.sourceAppName)")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.relativeTimestamp(for: group.clips.first?.createdAt ?? Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: model.expandedGroupIDs.contains(group.id) ? "chevron.up" : "chevron.down")
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowCardBackground(pinned: false, hovered: isHovered))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture {
            model.toggleGroupExpansion(group.id)
        }
    }
}

private struct ClipRowView: View {
    @EnvironmentObject private var model: AppModel

    let clip: ClipRecord
    @State private var isHovered = false

    private var rowHeight: CGFloat {
        model.settings.compactMode ? 50 : 62
    }

    var body: some View {
        HStack(spacing: 10) {
            preview

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.effectiveTitle)
                    .font(textFont)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if model.settings.showSourceAppIcons {
                        Image(nsImage: model.sourceIcon(for: clip))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }

                    Text(clip.sourceAppName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(model.relativeTimestamp(for: clip.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            Button {
                model.togglePinned(clip)
            } label: {
                Image(systemName: clip.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(clip.isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowCardBackground(pinned: clip.isPinned, hovered: isHovered))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            model.selectClip(clip)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy") {
                model.copyClip(clip)
            }
            Button("Paste") {
                model.pasteClip(clip)
            }
            Button(clip.isPinned ? "Unpin" : "Pin") {
                model.togglePinned(clip)
            }
            if clip.isPinned {
                Button("Rename Pin…") {
                    let renamed = DialogService.promptForPinName(currentValue: clip.pinTitle)
                    model.renamePin(clip, title: renamed)
                }
            }
            Divider()
            Button("Delete") {
                model.deleteClip(clip)
            }
        }
    }

    private var textFont: Font {
        clip.kind == .code
            ? .system(size: 12, weight: .medium, design: .monospaced)
            : .system(size: 13, weight: .medium)
    }

    @ViewBuilder
    private var preview: some View {
        switch clip.kind {
        case .image:
            if let image = model.previewImage(for: clip) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipped()
                    .cornerRadius(8)
            } else {
                iconPreview(symbol: "photo")
            }
        case .url:
            iconPreview(symbol: "globe")
        case .file:
            iconPreview(symbol: "doc")
        case .code:
            iconPreview(symbol: "curlybraces")
        case .richText:
            iconPreview(symbol: "text.quote")
        case .text:
            iconPreview(symbol: "text.alignleft")
        }
    }

    private func iconPreview(symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct PinnedClipDropDelegate: DropDelegate {
    let targetID: UUID
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedID = model.draggedPinnedClipID, draggedID != targetID else {
            return
        }
        model.movePinnedClip(draggedID: draggedID, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.draggedPinnedClipID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private func rowCardBackground(pinned: Bool, hovered: Bool) -> some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: pinned ? .controlAccentColor.withAlphaComponent(0.12) : .windowBackgroundColor).opacity(hovered ? 0.9 : 0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
}
