import CoreGraphics
import Foundation
import ImageIO

private struct Options {
    var imagePath = ""
    var roi = NormalizedRect(x: 0.35, y: 0.35, width: 0.40, height: 0.40)
    var minPixels = 25
    var step = 2
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

    var average: (red: Int, green: Int, blue: Int) {
        guard pixels > 0 else {
            return (0, 0, 0)
        }
        return (redTotal / pixels, greenTotal / pixels, blueTotal / pixels)
    }

    mutating func add(red: UInt8, green: UInt8, blue: UInt8) {
        pixels += 1
        redTotal += Int(red)
        greenTotal += Int(green)
        blueTotal += Int(blue)
    }
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

            print("color_swatch_check image=\(options.imagePath)")
            print(
                "color_swatch_roi x=\(options.roi.x) y=\(options.roi.y)"
                    + " width=\(options.roi.width) height=\(options.roi.height)"
                    + " min_pixels=\(options.minPixels) step=\(options.step)"
            )
            for swatch in Swatch.allCases {
                let swatchStats = stats[swatch] ?? SwatchStats()
                let avg = swatchStats.average
                print(
                    "color_swatch name=\(swatch.rawValue)"
                        + " pixels=\(swatchStats.pixels)"
                        + " avg_r=\(avg.red) avg_g=\(avg.green) avg_b=\(avg.blue)"
                )
            }

            if failures.isEmpty {
                print("color_swatch_summary status=passed")
                exit(0)
            }

            fputs(
                "color_swatch_summary status=failed missing=\(failures.map(\.rawValue).joined(separator: ","))\n",
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
        dominant pixels from the display_ocr_check calibration swatches.
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

        var stats = Dictionary(uniqueKeysWithValues: Swatch.allCases.map { ($0, SwatchStats()) })

        for y in stride(from: y0, to: y1, by: options.step) {
            for x in stride(from: x0, to: x1, by: options.step) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = pixels[offset]
                let green = pixels[offset + 1]
                let blue = pixels[offset + 2]
                if let swatch = classify(red: red, green: green, blue: blue) {
                    stats[swatch]?.add(red: red, green: green, blue: blue)
                }
            }
        }

        return stats
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
