import CoreGraphics
import Foundation
import ImageIO

private struct Options {
    var imagePath = ""
    var roi = NormalizedRect(x: 0.35, y: 0.35, width: 0.40, height: 0.40)
    var minPixels = 25
    var step = 2
    var requireGeometry = true
    var minXGap = 20.0
    var maxYSpread = 45.0
}

private struct NormalizedRect {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private enum Swatch: String, CaseIterable {
    case red
    case green
    case blue
    case yellow
}

private struct SwatchStats {
    var pixels = 0
    var redTotal = 0
    var greenTotal = 0
    var blueTotal = 0
    var xTotal = 0
    var yTotal = 0
    var minX = Int.max
    var minY = Int.max
    var maxX = Int.min
    var maxY = Int.min

    var average: (red: Int, green: Int, blue: Int) {
        guard pixels > 0 else {
            return (0, 0, 0)
        }
        return (redTotal / pixels, greenTotal / pixels, blueTotal / pixels)
    }

    var center: (x: Double, y: Double)? {
        guard pixels > 0 else {
            return nil
        }
        return (Double(xTotal) / Double(pixels), Double(yTotal) / Double(pixels))
    }

    var bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        guard pixels > 0 else {
            return nil
        }
        return (minX, minY, maxX, maxY)
    }

    mutating func add(red: UInt8, green: UInt8, blue: UInt8, x: Int, y: Int) {
        pixels += 1
        redTotal += Int(red)
        greenTotal += Int(green)
        blueTotal += Int(blue)
        xTotal += x
        yTotal += y
        minX = Swift.min(minX, x)
        minY = Swift.min(minY, y)
        maxX = Swift.max(maxX, x)
        maxY = Swift.max(maxY, y)
    }
}

private struct Sample {
    let x: Int
    let y: Int
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

private enum ColorSwatchError: Error, CustomStringConvertible {
    case usage(String)
    case loadFailed(String)
    case invalidImage
    case invalidROI(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .loadFailed(let path):
            return "Could not load image: \(path)"
        case .invalidImage:
            return "Image could not be converted to RGBA pixels."
        case .invalidROI(let value):
            return "ROI must be normalized as x,y,w,h within 0.0...1.0: \(value)"
        }
    }
}

@main
private struct ColorSwatchCheck {
    static func main() {
        do {
            let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
            guard !options.imagePath.isEmpty else {
                throw ColorSwatchError.usage("Missing --image <path>.")
            }
            let image = try loadImage(at: options.imagePath)
            let stats = try analyze(image: image, options: options)
            let failures = Swatch.allCases.filter { swatch in
                (stats[swatch]?.pixels ?? 0) < options.minPixels
            }
            let geometryFailures = options.requireGeometry && failures.isEmpty
                ? validateGeometry(stats: stats, options: options)
                : []

            print("color_swatch_check image=\(options.imagePath)")
            print(
                "color_swatch_roi x=\(options.roi.x) y=\(options.roi.y)"
                    + " width=\(options.roi.width) height=\(options.roi.height)"
                    + " min_pixels=\(options.minPixels) step=\(options.step)"
                    + " geometry=\(options.requireGeometry ? 1 : 0)"
            )
            for swatch in Swatch.allCases {
                let swatchStats = stats[swatch] ?? SwatchStats()
                let avg = swatchStats.average
                let center = swatchStats.center
                let bounds = swatchStats.bounds
                print(
                    "color_swatch name=\(swatch.rawValue)"
                        + " pixels=\(swatchStats.pixels)"
                        + " avg_r=\(avg.red) avg_g=\(avg.green) avg_b=\(avg.blue)"
                        + " center_x=\(format(center?.x)) center_y=\(format(center?.y))"
                        + " bounds=\(format(bounds))"
                )
            }

            if failures.isEmpty && geometryFailures.isEmpty {
                print("color_swatch_summary status=passed")
                exit(0)
            }

            let missing = failures.map(\.rawValue).joined(separator: ",")
            let geometry = geometryFailures.joined(separator: ",")
            fputs(
                "color_swatch_summary status=failed missing=\(missing) geometry=\(geometry)\n",
                stderr
            )
            exit(1)
        } catch {
            fputs("ColorSwatchCheck: \(error)\n", stderr)
            exit(2)
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--image":
                index += 1
                guard index < arguments.count else { throw ColorSwatchError.usage("Missing value for --image.") }
                options.imagePath = arguments[index]
            case "--roi":
                index += 1
                guard index < arguments.count else { throw ColorSwatchError.usage("Missing value for --roi.") }
                options.roi = try parseROI(arguments[index])
            case "--min-pixels":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
                    throw ColorSwatchError.usage("--min-pixels requires a positive integer.")
                }
                options.minPixels = value
            case "--step":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
                    throw ColorSwatchError.usage("--step requires a positive integer.")
                }
                options.step = value
            case "--min-x-gap":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value >= 0 else {
                    throw ColorSwatchError.usage("--min-x-gap requires a non-negative number.")
                }
                options.minXGap = value
            case "--max-y-spread":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value >= 0 else {
                    throw ColorSwatchError.usage("--max-y-spread requires a non-negative number.")
                }
                options.maxYSpread = value
            case "--skip-geometry":
                options.requireGeometry = false
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                throw ColorSwatchError.usage("Unknown argument: \(arg)")
            }
            index += 1
        }
        return options
    }

    private static func parseROI(_ value: String) throws -> NormalizedRect {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]),
              x >= 0.0,
              y >= 0.0,
              width > 0.0,
              height > 0.0,
              x + width <= 1.0,
              y + height <= 1.0 else {
            throw ColorSwatchError.invalidROI(value)
        }
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }

    private static func printUsage() {
        print("""
        Usage:
          ColorSwatchCheck --image /path/to/frame.jpg [--roi 0.35,0.35,0.40,0.40]

        The checker scans the center display ROI for red, green, blue, and yellow
        dominant pixels from the display_ocr_check calibration swatches, then
        checks that their centroids are left-to-right and row-aligned.
        """)
    }

    private static func loadImage(at path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ColorSwatchError.loadFailed(path)
        }
        return image
    }

    private static func analyze(image: CGImage, options: Options) throws -> [Swatch: SwatchStats] {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ColorSwatchError.invalidImage
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let x0 = max(0, Int((options.roi.x * Double(width)).rounded(.down)))
        let y0 = max(0, Int((options.roi.y * Double(height)).rounded(.down)))
        let x1 = min(width, Int(((options.roi.x + options.roi.width) * Double(width)).rounded(.up)))
        let y1 = min(height, Int(((options.roi.y + options.roi.height) * Double(height)).rounded(.up)))

        var samples = Dictionary(uniqueKeysWithValues: Swatch.allCases.map { ($0, [Sample]()) })

        for y in stride(from: y0, to: y1, by: options.step) {
            for x in stride(from: x0, to: x1, by: options.step) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = pixels[offset]
                let green = pixels[offset + 1]
                let blue = pixels[offset + 2]
                if let swatch = classify(red: red, green: green, blue: blue) {
                    samples[swatch]?.append(Sample(x: x, y: y, red: red, green: green, blue: blue))
                }
            }
        }

        return Dictionary(
            uniqueKeysWithValues: Swatch.allCases.map { swatch in
                (swatch, largestConnectedStats(samples: samples[swatch] ?? [], step: options.step))
            }
        )
    }

    private static func largestConnectedStats(samples: [Sample], step: Int) -> SwatchStats {
        guard !samples.isEmpty else {
            return SwatchStats()
        }

        let keyedSamples = Dictionary(uniqueKeysWithValues: samples.map { (pointKey(x: $0.x, y: $0.y), $0) })
        var visited = Set<Int64>()
        var best = SwatchStats()
        let neighborStride = step
        let neighborOffsets = [
            (-neighborStride, -neighborStride), (0, -neighborStride), (neighborStride, -neighborStride),
            (-neighborStride, 0), (neighborStride, 0),
            (-neighborStride, neighborStride), (0, neighborStride), (neighborStride, neighborStride),
        ]

        for sample in samples {
            let startKey = pointKey(x: sample.x, y: sample.y)
            if visited.contains(startKey) {
                continue
            }

            var component = SwatchStats()
            var stack = [sample]
            visited.insert(startKey)

            while let current = stack.popLast() {
                component.add(red: current.red, green: current.green, blue: current.blue, x: current.x, y: current.y)
                for offset in neighborOffsets {
                    let nx = current.x + offset.0
                    let ny = current.y + offset.1
                    let key = pointKey(x: nx, y: ny)
                    if visited.contains(key) {
                        continue
                    }
                    guard let neighbor = keyedSamples[key] else {
                        continue
                    }
                    visited.insert(key)
                    stack.append(neighbor)
                }
            }

            if component.pixels > best.pixels {
                best = component
            }
        }

        return best
    }

    private static func pointKey(x: Int, y: Int) -> Int64 {
        (Int64(y) << 32) | Int64(UInt32(bitPattern: Int32(x)))
    }

    private static func validateGeometry(stats: [Swatch: SwatchStats], options: Options) -> [String] {
        let centers = Swatch.allCases.compactMap { swatch -> (swatch: Swatch, x: Double, y: Double)? in
            guard let center = stats[swatch]?.center else {
                return nil
            }
            return (swatch, center.x, center.y)
        }
        guard centers.count == Swatch.allCases.count else {
            return ["centers-missing"]
        }

        var failures: [String] = []
        for pair in zip(centers, centers.dropFirst()) {
            if pair.1.x - pair.0.x < options.minXGap {
                failures.append("\(pair.0.swatch.rawValue)-before-\(pair.1.swatch.rawValue)")
            }
        }

        let yValues = centers.map(\.y)
        if let minY = yValues.min(), let maxY = yValues.max(), maxY - minY > options.maxYSpread {
            failures.append("row-spread-\(format(maxY - minY))")
        }
        return failures
    }

    private static func format(_ value: Double?) -> String {
        guard let value else {
            return "na"
        }
        return String(format: "%.1f", value)
    }

    private static func format(_ bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?) -> String {
        guard let bounds else {
            return "na"
        }
        return "\(bounds.minX),\(bounds.minY),\(bounds.maxX),\(bounds.maxY)"
    }

    private static func classify(red: UInt8, green: UInt8, blue: UInt8) -> Swatch? {
        let r = Int(red)
        let g = Int(green)
        let b = Int(blue)
        let brightness = r + g + b
        guard brightness > 70 else {
            return nil
        }

        if r > 65, r > g * 3 / 2, r > b * 3 / 2 {
            return .red
        }
        if g > 45, g > r * 6 / 5, g > b * 6 / 5 {
            return .green
        }
        if b > 65, b > r * 3 / 2, b > g * 3 / 2 {
            return .blue
        }
        if r > 95, g > 80, b < min(r, g) * 4 / 5, abs(r - g) < 90 {
            return .yellow
        }
        return nil
    }
}
