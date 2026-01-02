import SwiftUI

struct QuadrantOverlayView: View {
    let quadrantData: QuadrantData
    let showQuadrants: Bool
    let flipHorizontally: Bool
    let flipVertically: Bool
    let temperatureUnit: TemperatureUnit
    let onXSplitChanged: (Int) -> Void
    let onYSplitChanged: (Int) -> Void

    // Track drag state locally for smooth visual updates
    @State private var dragXSplit: Int? = nil
    @State private var dragYSplit: Int? = nil
    @State private var activeDrag: DragAxis? = nil

    private enum DragAxis {
        case horizontal  // dragging vertical line left/right
        case vertical    // dragging horizontal line up/down
    }

    private let lineColor = Color.cyan.opacity(0.8)
    private let dragLineColor = Color.cyan
    private let lineWidth: CGFloat = 2
    private let dragLineWidth: CGFloat = 3

    // Current display values (use drag value if dragging, otherwise quadrantData)
    private var displayXSplit: Int {
        dragXSplit ?? quadrantData.xSplit
    }

    private var displayYSplit: Int {
        dragYSplit ?? quadrantData.ySplit
    }

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

                    // Gesture hit areas near the lines
                    gestureOverlay(in: geometry)
                }
            }
        }
    }

    // Gesture overlay that captures drags near either line
    private func gestureOverlay(in geometry: GeometryProxy) -> some View {
        let xPos = xPosition(in: geometry)
        let yPos = yPosition(in: geometry)

        return ZStack {
            // Hit area around vertical line
            Rectangle()
                .fill(Color.clear)
                .frame(width: 44, height: geometry.size.height)
                .position(x: xPos, y: geometry.size.height / 2)
                .contentShape(Rectangle())

            // Hit area around horizontal line
            Rectangle()
                .fill(Color.clear)
                .frame(width: geometry.size.width, height: 44)
                .position(x: geometry.size.width / 2, y: yPos)
                .contentShape(Rectangle())
        }
        .gesture(combinedDragGesture(in: geometry))
    }

    // MARK: - Divider Lines

    private func verticalDivider(in geometry: GeometryProxy) -> some View {
        let xPos = xPosition(in: geometry)
        let isDragging = dragXSplit != nil

        return ZStack {
            // Visible line
            Rectangle()
                .fill(isDragging ? dragLineColor : lineColor)
                .frame(width: isDragging ? dragLineWidth : lineWidth)
                .position(x: xPos, y: geometry.size.height / 2)

            // Invisible drag handle (wider hit area)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 44, height: geometry.size.height)
                .position(x: xPos, y: geometry.size.height / 2)
                .contentShape(Rectangle())
        }
    }

    private func horizontalDivider(in geometry: GeometryProxy) -> some View {
        let yPos = yPosition(in: geometry)
        let isDragging = dragYSplit != nil

        return ZStack {
            // Visible line
            Rectangle()
                .fill(isDragging ? dragLineColor : lineColor)
                .frame(height: isDragging ? dragLineWidth : lineWidth)
                .position(x: geometry.size.width / 2, y: yPos)

            // Invisible drag handle (taller hit area)
            Rectangle()
                .fill(Color.clear)
                .frame(width: geometry.size.width, height: 44)
                .position(x: geometry.size.width / 2, y: yPos)
                .contentShape(Rectangle())
        }
    }

    // Combined gesture that determines direction based on initial movement
    private func combinedDragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                // Determine drag direction on first significant movement
                if activeDrag == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx > dy {
                        activeDrag = .horizontal  // Moving left/right -> vertical line
                    } else {
                        activeDrag = .vertical    // Moving up/down -> horizontal line
                    }
                }

                // Update the appropriate split based on active drag
                switch activeDrag {
                case .horizontal:
                    let newX = pixelX(from: value.location.x, in: geometry)
                    dragXSplit = newX
                case .vertical:
                    let newY = pixelY(from: value.location.y, in: geometry)
                    dragYSplit = newY
                case .none:
                    break
                }
            }
            .onEnded { value in
                // Send command based on which axis was being dragged
                switch activeDrag {
                case .horizontal:
                    let newX = pixelX(from: value.location.x, in: geometry)
                    onXSplitChanged(newX)
                case .vertical:
                    let newY = pixelY(from: value.location.y, in: geometry)
                    onYSplitChanged(newY)
                case .none:
                    break
                }

                // Reset state
                dragXSplit = nil
                dragYSplit = nil
                activeDrag = nil
            }
    }

    // MARK: - Quadrant Labels

    private func quadrantLabels(in geometry: GeometryProxy) -> some View {
        let xSplit = xPosition(in: geometry)
        let ySplit = yPosition(in: geometry)

        // Determine which quadrant data appears in each screen position based on flip states
        // Original layout: A=top-left, B=top-right, C=bottom-left, D=bottom-right
        // Horizontal flip: swap left↔right (A↔B, C↔D)
        // Vertical flip: swap top↔bottom (A↔C, B↔D)
        let topLeftQuadrant: (label: String, max: UInt16, center: UInt16) = {
            switch (flipHorizontally, flipVertically) {
            case (false, false): return ("A", quadrantData.aMax, quadrantData.aCenter)
            case (true, false):  return ("B", quadrantData.bMax, quadrantData.bCenter)
            case (false, true):  return ("C", quadrantData.cMax, quadrantData.cCenter)
            case (true, true):   return ("D", quadrantData.dMax, quadrantData.dCenter)
            }
        }()

        let topRightQuadrant: (label: String, max: UInt16, center: UInt16) = {
            switch (flipHorizontally, flipVertically) {
            case (false, false): return ("B", quadrantData.bMax, quadrantData.bCenter)
            case (true, false):  return ("A", quadrantData.aMax, quadrantData.aCenter)
            case (false, true):  return ("D", quadrantData.dMax, quadrantData.dCenter)
            case (true, true):   return ("C", quadrantData.cMax, quadrantData.cCenter)
            }
        }()

        let bottomLeftQuadrant: (label: String, max: UInt16, center: UInt16) = {
            switch (flipHorizontally, flipVertically) {
            case (false, false): return ("C", quadrantData.cMax, quadrantData.cCenter)
            case (true, false):  return ("D", quadrantData.dMax, quadrantData.dCenter)
            case (false, true):  return ("A", quadrantData.aMax, quadrantData.aCenter)
            case (true, true):   return ("B", quadrantData.bMax, quadrantData.bCenter)
            }
        }()

        let bottomRightQuadrant: (label: String, max: UInt16, center: UInt16) = {
            switch (flipHorizontally, flipVertically) {
            case (false, false): return ("D", quadrantData.dMax, quadrantData.dCenter)
            case (true, false):  return ("C", quadrantData.cMax, quadrantData.cCenter)
            case (false, true):  return ("B", quadrantData.bMax, quadrantData.bCenter)
            case (true, true):   return ("A", quadrantData.aMax, quadrantData.aCenter)
            }
        }()

        return Group {
            // Top-left quadrant
            quadrantLabel(
                label: topLeftQuadrant.label,
                maxTemp: topLeftQuadrant.max,
                centerTemp: topLeftQuadrant.center
            )
            .position(x: xSplit / 2, y: ySplit / 2)

            // Top-right quadrant
            quadrantLabel(
                label: topRightQuadrant.label,
                maxTemp: topRightQuadrant.max,
                centerTemp: topRightQuadrant.center
            )
            .position(x: xSplit + (geometry.size.width - xSplit) / 2, y: ySplit / 2)

            // Bottom-left quadrant
            quadrantLabel(
                label: bottomLeftQuadrant.label,
                maxTemp: bottomLeftQuadrant.max,
                centerTemp: bottomLeftQuadrant.center
            )
            .position(x: xSplit / 2, y: ySplit + (geometry.size.height - ySplit) / 2)

            // Bottom-right quadrant
            quadrantLabel(
                label: bottomRightQuadrant.label,
                maxTemp: bottomRightQuadrant.max,
                centerTemp: bottomRightQuadrant.center
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
        let xSplit = flipHorizontally ? (ThermalProtocol.frameWidth - displayXSplit) : displayXSplit
        return CGFloat(xSplit) * pixelWidth
    }

    private func yPosition(in geometry: GeometryProxy) -> CGFloat {
        let pixelHeight = geometry.size.height / CGFloat(ThermalProtocol.imageHeight)
        let ySplit = flipVertically ? (ThermalProtocol.imageHeight - displayYSplit) : displayYSplit
        return CGFloat(ySplit) * pixelHeight
    }

    private func pixelX(from screenX: CGFloat, in geometry: GeometryProxy) -> Int {
        let pixelWidth = geometry.size.width / CGFloat(ThermalProtocol.frameWidth)
        var pixel = Int(screenX / pixelWidth)
        if flipHorizontally {
            pixel = ThermalProtocol.frameWidth - pixel
        }
        return max(1, min(79, pixel))
    }

    private func pixelY(from screenY: CGFloat, in geometry: GeometryProxy) -> Int {
        let pixelHeight = geometry.size.height / CGFloat(ThermalProtocol.imageHeight)
        var pixel = Int(screenY / pixelHeight)
        if flipVertically {
            pixel = ThermalProtocol.imageHeight - pixel
        }
        return max(1, min(61, pixel))
    }
}
