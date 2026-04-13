import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: PanelStore

    var body: some View {
        ZStack {
            CmdScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.panels.enumerated()), id: \.element.id) { index, panel in
                        if index > 0 {
                            RowResizableDivider(
                                topPanel: store.panels[index - 1],
                                bottomPanel: panel
                            )
                        }
                        RowView(
                            panel: panel,
                            index: index + 1,
                            fontSize: store.fontSize,
                            height: panel.height,
                            focusedCellID: store.focusedCellID,
                            onClose: { store.removePanel(id: panel.id) }
                        )
                    }
                }
                .padding(Theme.panelSpacing)
            }
            .background(Theme.background)

            if store.showHelp {
                HelpOverlay(isPresented: $store.showHelp)
            }
        }
    }
}

struct RowResizableDivider: View {
    @ObservedObject var topPanel: PanelModel
    @ObservedObject var bottomPanel: PanelModel

    static let hitAreaHeight: CGFloat = 16
    private static let minHeight: CGFloat = 200

    @State private var isHovering = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Color.clear
                .frame(height: Self.hitAreaHeight)
                .contentShape(Rectangle())

            Rectangle()
                .fill(isHovering || isDragging ? Theme.focusBorder : Theme.border)
                .frame(height: isDragging ? 4 : 1)

            HStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(isHovering || isDragging ? Theme.focusBorder : Theme.textSecondary)
                        .frame(width: isDragging ? 5 : 3, height: isDragging ? 5 : 3)
                }
            }
        }
        .frame(height: Self.hitAreaHeight)
        .offset(y: isDragging ? dragOffset : 0)
        .allowsHitTesting(true)
        .zIndex(1)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.height
                }
                .onEnded { _ in
                    let proposedTop = topPanel.height + dragOffset
                    let total = topPanel.height + bottomPanel.height
                    let clampedTop = max(Self.minHeight, min(total - Self.minHeight, proposedTop))
                    let clampedBottom = total - clampedTop
                    if clampedTop != topPanel.height {
                        topPanel.height = clampedTop
                        bottomPanel.height = clampedBottom
                    }
                    dragOffset = 0
                    isDragging = false
                }
        )
    }
}
