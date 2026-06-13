import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count >= 2 else {
  fputs("Usage: vision-ocr.swift <image-path>\n", stderr)
  exit(2)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)

guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fputs("Could not load image: \(imagePath)\n", stderr)
  exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages = ["en-US"]
request.minimumTextHeight = 0.015

let handler = VNImageRequestHandler(cgImage: image, options: [:])

do {
  try handler.perform([request])
} catch {
  fputs("Vision OCR failed: \(error)\n", stderr)
  exit(1)
}

let observations = request.results ?? []

for observation in observations {
  guard let candidate = observation.topCandidates(1).first else {
    continue
  }
  print(candidate.string)
}

