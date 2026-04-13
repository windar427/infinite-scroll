import SwiftUI

struct RowView: View {
    @ObservedObject var panel: PanelModel
    let index: Int
    let fontSize: CGFloat
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
            .frame(height: Theme.panelHeight - Theme.headerHeight)
        }
        .frame(height: Theme.panelHeight)
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
    static let hitAreaWidth: CGFloat = 8
    /// Minimum pixel width a cell can be dragged to.
    private static let minCellWidth: CGFloat = 100

    @State private var isHovering = false
    /// Snapshot of left/right fractions at drag start, so cumulative translation works correctly.
    @State private var dragStartLeft: CGFloat = 0
    @State private var dragStartRight: CGFloat = 0

    var body: some View {
        ZStack {
            // Invisible wide hit area
            Color.clear
                .frame(width: Self.hitAreaWidth)
                .contentShape(Rectangle())

            // Visible 1px line
            Rectangle()
                .fill(isHovering ? Theme.focusBorder : Theme.border)
                .frame(width: 1)
        }
        .frame(width: Self.hitAreaWidth)
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
                    // On first drag event, snapshot the initial fractions
                    if dragStartLeft == 0 && dragStartRight == 0 {
                        dragStartLeft = leftCell.widthFraction
                        dragStartRight = rightCell.widthFraction
                    }

                    guard totalFractions > 0, availableWidth > 0 else { return }

                    let fractionPerPoint = totalFractions / availableWidth
                    let deltaFraction = value.translation.width * fractionPerPoint

                    // Compute proposed fractions from the drag-start snapshot
                    let proposedLeft = dragStartLeft + deltaFraction
                    let proposedRight = dragStartRight - deltaFraction

                    // Convert minimum width to minimum fraction
                    let minFraction = Self.minCellWidth * fractionPerPoint

                    guard proposedLeft >= minFraction, proposedRight >= minFraction else { return }

                    leftCell.widthFraction = proposedLeft
                    rightCell.widthFraction = proposedRight
                }
                .onEnded { _ in
                    dragStartLeft = 0
                    dragStartRight = 0
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
