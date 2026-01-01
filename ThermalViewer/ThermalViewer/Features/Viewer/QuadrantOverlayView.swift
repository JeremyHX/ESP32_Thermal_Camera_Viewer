import SwiftUI

struct QuadrantOverlayView: View {
    let quadrantData: QuadrantData
    let showQuadrants: Bool
    let isFlipped: Bool
    let temperatureUnit: TemperatureUnit
    let onXSplitChanged: (Int) -> Void
    let onYSplitChanged: (Int) -> Void

    @GestureState private var isDraggingX = false
    @GestureState private var isDraggingY = false

    private let lineColor = Color.cyan.opacity(0.8)
    private let lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            if showQuadrants {
                ZStack {
                    // Vertical divider line (X split)
                    verticalDivider(in: geometry)

                    // Horizontal divider line (Y split)
                    horizontalDivider(in: geometry)

                    // Quadrant labels
                    quadrantLabels(in: geometry)
                }
            }
        }
    }

    // MARK: - Divider Lines

    private func verticalDivider(in geometry: GeometryProxy) -> some View {
        let xPos = xPosition(in: geometry)

        return Rectangle()
            .fill(lineColor)
            .frame(width: lineWidth)
            .position(x: xPos, y: geometry.size.height / 2)
            .gesture(
                DragGesture()
                    .updating($isDraggingX) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let newX = pixelX(from: value.location.x, in: geometry)
                        onXSplitChanged(newX)
                    }
            )
            .overlay(
                // Drag handle
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 30, height: geometry.size.height)
                    .position(x: xPos, y: geometry.size.height / 2)
                    .contentShape(Rectangle())
            )
    }

    private func horizontalDivider(in geometry: GeometryProxy) -> some View {
        let yPos = yPosition(in: geometry)

        return Rectangle()
            .fill(lineColor)
            .frame(height: lineWidth)
            .position(x: geometry.size.width / 2, y: yPos)
            .gesture(
                DragGesture()
                    .updating($isDraggingY) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let newY = pixelY(from: value.location.y, in: geometry)
                        onYSplitChanged(newY)
                    }
            )
            .overlay(
                // Drag handle
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width, height: 30)
                    .position(x: geometry.size.width / 2, y: yPos)
                    .contentShape(Rectangle())
            )
    }

    // MARK: - Quadrant Labels

    private func quadrantLabels(in geometry: GeometryProxy) -> some View {
        let xSplit = xPosition(in: geometry)
        let ySplit = yPosition(in: geometry)

        // Determine label positions based on flip state
        let leftLabel = isFlipped ? "B" : "A"
        let rightLabel = isFlipped ? "A" : "B"
        let bottomLeftLabel = isFlipped ? "D" : "C"
        let bottomRightLabel = isFlipped ? "C" : "D"

        return Group {
            // Top-left quadrant
            quadrantLabel(
                label: leftLabel,
                maxTemp: isFlipped ? quadrantData.bMax : quadrantData.aMax,
                centerTemp: isFlipped ? quadrantData.bCenter : quadrantData.aCenter
            )
            .position(x: xSplit / 2, y: ySplit / 2)

            // Top-right quadrant
            quadrantLabel(
                label: rightLabel,
                maxTemp: isFlipped ? quadrantData.aMax : quadrantData.bMax,
                centerTemp: isFlipped ? quadrantData.aCenter : quadrantData.bCenter
            )
            .position(x: xSplit + (geometry.size.width - xSplit) / 2, y: ySplit / 2)

            // Bottom-left quadrant
            quadrantLabel(
                label: bottomLeftLabel,
                maxTemp: isFlipped ? quadrantData.dMax : quadrantData.cMax,
                centerTemp: isFlipped ? quadrantData.dCenter : quadrantData.cCenter
            )
            .position(x: xSplit / 2, y: ySplit + (geometry.size.height - ySplit) / 2)

            // Bottom-right quadrant
            quadrantLabel(
                label: bottomRightLabel,
                maxTemp: isFlipped ? quadrantData.cMax : quadrantData.dMax,
                centerTemp: isFlipped ? quadrantData.cCenter : quadrantData.dCenter
            )
            .position(x: xSplit + (geometry.size.width - xSplit) / 2, y: ySplit + (geometry.size.height - ySplit) / 2)
        }
    }

    private func quadrantLabel(label: String, maxTemp: UInt16, centerTemp: UInt16) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Text("Max: \(temperatureUnit.format(maxTemp))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.yellow)

            Text("Ctr: \(temperatureUnit.format(centerTemp))")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(6)
        .background(Color.black.opacity(0.5))
        .cornerRadius(6)
    }

    // MARK: - Coordinate Conversion

    private func xPosition(in geometry: GeometryProxy) -> CGFloat {
        let pixelWidth = geometry.size.width / CGFloat(ThermalProtocol.frameWidth)
        let xSplit = isFlipped ? (ThermalProtocol.frameWidth - quadrantData.xSplit) : quadrantData.xSplit
        return CGFloat(xSplit) * pixelWidth
    }

    private func yPosition(in geometry: GeometryProxy) -> CGFloat {
        let pixelHeight = geometry.size.height / CGFloat(ThermalProtocol.imageHeight)
        return CGFloat(quadrantData.ySplit) * pixelHeight
    }

    private func pixelX(from screenX: CGFloat, in geometry: GeometryProxy) -> Int {
        let pixelWidth = geometry.size.width / CGFloat(ThermalProtocol.frameWidth)
        var pixel = Int(screenX / pixelWidth)
        if isFlipped {
            pixel = ThermalProtocol.frameWidth - pixel
        }
        return max(1, min(79, pixel))
    }

    private func pixelY(from screenY: CGFloat, in geometry: GeometryProxy) -> Int {
        let pixelHeight = geometry.size.height / CGFloat(ThermalProtocol.imageHeight)
        let pixel = Int(screenY / pixelHeight)
        return max(1, min(61, pixel))
    }
}
