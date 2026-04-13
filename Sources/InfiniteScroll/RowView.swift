import SwiftUI
import AppKit

struct RowView: View {
    @ObservedObject var panel: PanelModel
    let index: Int
    let fontSize: CGFloat
    let height: CGFloat
    let focusedCellID: UUID?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(panel.title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.text)

                Spacer()

                Button(action: { panel.toggleNotes() }) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(panel.showNotes ? Theme.focusBorder : Theme.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.arrow.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Theme.headerHeight)
            .background(Theme.headerBackground)

            // Dynamic cells — proportional width with draggable dividers
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(panel.cells.enumerated()), id: \.element.id) { idx, cell in
                        if idx > 0 {
                            ResizableDivider(
                                leftCell: panel.cells[idx - 1],
                                rightCell: cell,
                                availableWidth: availableWidth(total: geo.size.width),
                                totalFractions: totalFractions
                            )
                        }
                        CellView(cell: cell, fontSize: fontSize)
                            .frame(width: cellWidth(cell: cell, total: geo.size.width))
                            .overlay(
                                Rectangle()
                                    .stroke(
                                        focusedCellID == cell.id ? Theme.focusBorder : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                }
            }
            .frame(height: height - Theme.headerHeight)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    /// Sum of all cells' widthFraction values.
    private var totalFractions: CGFloat {
        panel.cells.reduce(0) { $0 + $1.widthFraction }
    }

    /// Total width available for cell content (minus divider hit areas).
    private func availableWidth(total: CGFloat) -> CGFloat {
        let dividerCount = CGFloat(max(panel.cells.count - 1, 0))
        return max(0, total - dividerCount * ResizableDivider.hitAreaWidth)
    }

    /// Width of a single cell based on its fraction of total fractions.
    private func cellWidth(cell: CellModel, total: CGFloat) -> CGFloat {
        let fractions = totalFractions
        guard fractions > 0 else { return 0 }
        return (cell.widthFraction / fractions) * availableWidth(total: total)
    }

    private var statusColor: Color {
        let anyRunning = panel.cells.contains { $0.type == .terminal && $0.isRunning }
        return anyRunning ? .green : .gray
    }
}

// MARK: - ResizableDivider: draggable divider between cells

struct ResizableDivider: View {
    @ObservedObject var leftCell: CellModel
    @ObservedObject var rightCell: CellModel
    let availableWidth: CGFloat
    let totalFractions: CGFloat

    /// Total visible+hit width of the divider.
    static let hitAreaWidth: CGFloat = 16
    /// Minimum pixel width a cell can be dragged to.
    private static let minCellWidth: CGFloat = 100

    @State private var isHovering = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: Self.hitAreaWidth)
                .contentShape(Rectangle())

            Rectangle()
                .fill(isHovering || isDragging ? Theme.focusBorder : Theme.border)
                .frame(width: isDragging ? 4 : 1)

            VStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(isHovering || isDragging ? Theme.focusBorder : Theme.textSecondary)
                        .frame(width: isDragging ? 5 : 3, height: isDragging ? 5 : 3)
                }
            }
        }
        .frame(width: Self.hitAreaWidth)
        .offset(x: isDragging ? dragOffset : 0)
        .allowsHitTesting(true)
        .zIndex(1)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { _ in
                    if totalFractions > 0, availableWidth > 0 {
                        let fractionPerPoint = totalFractions / availableWidth
                        let minFraction = Self.minCellWidth * fractionPerPoint
                        let maxLeftDelta = (rightCell.widthFraction - minFraction) / fractionPerPoint
                        let maxRightDelta = (leftCell.widthFraction - minFraction) / fractionPerPoint
                        let clamped = max(-maxRightDelta, min(maxLeftDelta, dragOffset))
                        let deltaFraction = clamped * fractionPerPoint
                        leftCell.widthFraction += deltaFraction
                        rightCell.widthFraction -= deltaFraction
                    }
                    dragOffset = 0
                    isDragging = false
                }
        )
    }
}

// MARK: - CellView: renders a terminal or notes cell

struct CellView: View {
    @ObservedObject var cell: CellModel
    let fontSize: CGFloat

    var body: some View {
        switch cell.type {
        case .terminal:
            TerminalWrapper(
                terminalID: cell.id,
                initialDirectory: cell.cwd,
                fontSize: fontSize,
                onExit: { _ in cell.isRunning = false },
                onCwdChange: { cwd in cell.cwd = cwd }
            )
        case .notes:
            MarkdownNotesView(
                notesID: cell.id,
                text: $cell.text,
                fontSize: fontSize
            )
        case .excalidraw:
            ExcalidrawView(
                excalidrawID: cell.id,
                text: $cell.text,
                fontSize: fontSize
            )
        }
    }
}
