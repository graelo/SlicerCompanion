import CoreGraphics
import Foundation

struct ToolpathPoint: Sendable {
    let x: Double
    let y: Double
}

struct ToolpathMove: Sendable {
    let start: ToolpathPoint
    let end: ToolpathPoint
    let layer: Int
    let extrudes: Bool
    let tool: Int
}

struct GCodeToolpath: Sendable {
    let moves: [ToolpathMove]
    let layerCount: Int

    private static let wordRegex = try! NSRegularExpression(
        pattern: #"([A-Za-z])\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))"#
    )

    static func parse(_ text: String, maximumMoves: Int = 500_000) -> GCodeToolpath {
        var moves: [ToolpathMove] = []
        var x = 0.0
        var y = 0.0
        var z = 0.0
        var e = 0.0
        var absoluteCoordinates = true
        var absoluteExtrusion = true
        var unitScale = 1.0
        var currentLayer = 0
        var currentTool = 0
        var hasSeenLayerZ = false
        var skipNextAutomaticLayer = false
        var maximumLayer = 0

        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            let code = parts[0]
            if parts.count > 1 {
                let comment = parts[1].trimmingCharacters(in: .whitespaces).uppercased()
                if comment.hasPrefix("LAYER:") {
                    if let layer = Int(comment.dropFirst("LAYER:".count).trimmingCharacters(in: .whitespaces)) {
                        currentLayer = max(0, layer)
                        maximumLayer = max(maximumLayer, currentLayer)
                        skipNextAutomaticLayer = true
                    }
                } else if comment.contains("LAYER_CHANGE") {
                    currentLayer += 1
                    maximumLayer = max(maximumLayer, currentLayer)
                    skipNextAutomaticLayer = true
                }
            }

            let words = Self.words(in: String(code))
            guard !words.isEmpty else { continue }
            let parameters = Dictionary(words.filter { !["G", "M", "T", "N"].contains($0.letter) }.map { ($0.letter, $0.value) }, uniquingKeysWith: { _, latest in latest })
            let gCode = words.first(where: { $0.letter == "G" }).map { Int($0.value.rounded()) }
            let mCode = words.first(where: { $0.letter == "M" }).map { Int($0.value.rounded()) }
            if let tool = words.first(where: { $0.letter == "T" }) {
                currentTool = max(0, Int(tool.value.rounded()))
            }

            switch gCode {
            case 20: unitScale = 25.4
            case 21: unitScale = 1
            case 90: absoluteCoordinates = true
            case 91: absoluteCoordinates = false
            case 92:
                if let value = parameters["X"] { x = value * unitScale }
                if let value = parameters["Y"] { y = value * unitScale }
                if let value = parameters["Z"] { z = value * unitScale }
                if let value = parameters["E"] { e = value * unitScale }
                continue
            default: break
            }

            switch mCode {
            case 82: absoluteExtrusion = true
            case 83: absoluteExtrusion = false
            default: break
            }

            guard let gCode, [0, 1, 2, 3].contains(gCode) else { continue }

            let start = ToolpathPoint(x: x, y: y)
            let startZ = z
            let startE = e
            if let value = parameters["X"] {
                x = absoluteCoordinates ? value * unitScale : x + value * unitScale
            }
            if let value = parameters["Y"] {
                y = absoluteCoordinates ? value * unitScale : y + value * unitScale
            }
            if let value = parameters["Z"] {
                z = absoluteCoordinates ? value * unitScale : z + value * unitScale
            }
            if let value = parameters["E"] {
                e = absoluteExtrusion ? value * unitScale : e + value * unitScale
            }

            if abs(z - startZ) > 0.0001 {
                if hasSeenLayerZ && !skipNextAutomaticLayer {
                    currentLayer += 1
                }
                hasSeenLayerZ = true
                maximumLayer = max(maximumLayer, currentLayer)
            }
            skipNextAutomaticLayer = false

            let end = ToolpathPoint(x: x, y: y)
            let extrudes = e - startE > 0.00001
            if gCode == 2 || gCode == 3,
               let i = parameters["I"], let j = parameters["J"] {
                let arcMoves = Self.arcMoves(
                    start: start,
                    end: end,
                    center: ToolpathPoint(x: start.x + i * unitScale, y: start.y + j * unitScale),
                    clockwise: gCode == 2,
                    layer: currentLayer,
                    extrudes: extrudes,
                    tool: currentTool
                )
                moves.append(contentsOf: arcMoves.prefix(max(0, maximumMoves - moves.count)))
            } else if abs(end.x - start.x) > 0.0001 || abs(end.y - start.y) > 0.0001 {
                moves.append(ToolpathMove(start: start, end: end, layer: currentLayer, extrudes: extrudes, tool: currentTool))
            }

            if moves.count >= maximumMoves { break }
        }

        return GCodeToolpath(moves: moves, layerCount: maximumLayer + 1)
    }

    func makeImage(layer selectedLayer: Int? = nil, width: Int = 1200, height: Int = 900) -> CGImage? {
        guard width > 0, height > 0, !moves.isEmpty else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let minX = moves.reduce(Double.infinity) { min($0, min($1.start.x, $1.end.x)) }
        let maxX = moves.reduce(-Double.infinity) { max($0, max($1.start.x, $1.end.x)) }
        let minY = moves.reduce(Double.infinity) { min($0, min($1.start.y, $1.end.y)) }
        let maxY = moves.reduce(-Double.infinity) { max($0, max($1.start.y, $1.end.y)) }
        let margin = 36.0
        let scale = min(
            (Double(width) - 2 * margin) / max(maxX - minX, 1),
            (Double(height) - 2 * margin) / max(maxY - minY, 1)
        )
        let drawWidth = (maxX - minX) * scale
        let drawHeight = (maxY - minY) * scale
        let offsetX = (Double(width) - drawWidth) / 2
        let offsetY = (Double(height) - drawHeight) / 2

        func point(_ point: ToolpathPoint) -> CGPoint {
            CGPoint(
                x: offsetX + (point.x - minX) * scale,
                y: Double(height) - offsetY - (point.y - minY) * scale
            )
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        for move in moves {
            if let selectedLayer, move.layer > selectedLayer { continue }
            if move.extrudes {
                context.setStrokeColor(move.layer == selectedLayer || selectedLayer == nil
                    ? CGColor(red: 0.88, green: 0.31, blue: 0.20, alpha: 0.9)
                    : CGColor(red: 0.28, green: 0.56, blue: 0.72, alpha: 0.22))
                context.setLineWidth(move.layer == selectedLayer ? 2.2 : 1.4)
            } else {
                context.setStrokeColor(CGColor(red: 0.56, green: 0.59, blue: 0.62, alpha: 0.35))
                context.setLineWidth(0.8)
            }
            context.beginPath()
            context.move(to: point(move.start))
            context.addLine(to: point(move.end))
            context.strokePath()
        }
        return context.makeImage()
    }

    private static func arcMoves(
        start: ToolpathPoint,
        end: ToolpathPoint,
        center: ToolpathPoint,
        clockwise: Bool,
        layer: Int,
        extrudes: Bool,
        tool: Int
    ) -> [ToolpathMove] {
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > 0.0001 else { return [] }

        var sweep = endAngle - startAngle
        if clockwise {
            if sweep >= 0 { sweep -= 2 * .pi }
        } else if sweep <= 0 {
            sweep += 2 * .pi
        }
        if abs(end.x - start.x) < 0.0001, abs(end.y - start.y) < 0.0001 {
            sweep = clockwise ? -2 * .pi : 2 * .pi
        }

        let count = min(360, max(2, Int(ceil(abs(sweep) / (.pi / 18)))))
        var result: [ToolpathMove] = []
        result.reserveCapacity(count)
        var previous = start
        for index in 1...count {
            let angle = startAngle + sweep * Double(index) / Double(count)
            let next = index == count ? end : ToolpathPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            result.append(ToolpathMove(start: previous, end: next, layer: layer, extrudes: extrudes, tool: tool))
            previous = next
        }
        return result
    }

    private static func words(in line: String) -> [(letter: String, value: Double)] {
        let nsLine = line as NSString
        return wordRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).compactMap { match in
            guard match.numberOfRanges == 3,
                  let value = Double(nsLine.substring(with: match.range(at: 2)) )
            else { return nil }
            return (nsLine.substring(with: match.range(at: 1)).uppercased(), value)
        }
    }
}