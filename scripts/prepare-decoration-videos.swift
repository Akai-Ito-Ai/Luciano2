// Genera copias para la web sin modificar los MP4 originales. Requiere macOS.
// Desde la carpeta del proyecto:
// swift -suppress-warnings -module-cache-path /tmp/luciano-swift-cache scripts/prepare-decoration-videos.swift
import Foundation
import AVFoundation
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("assets/decoraciones", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for number in 1...4 {
    let input = root.appendingPathComponent("assets/Dino\(number).mp4")
    let asset = AVURLAsset(url: input)
    guard let sourceTrack = asset.tracks(withMediaType: .video).first else {
        throw NSError(domain: "Luciano", code: 1, userInfo: [NSLocalizedDescriptionKey: "No hay video en \(input.lastPathComponent)"])
    }
    let destination = output.appendingPathComponent("dino\(number).mp4")
    // No sobrescribe una copia existente: eliminarla o renombrarla explícitamente antes de regenerar.
    guard !FileManager.default.fileExists(atPath: destination.path) else {
        print("Ya existe \(destination.lastPathComponent); se conserva.")
        continue
    }
    let reader = try AVAssetReader(asset: asset)
    let frames = AVAssetReaderTrackOutput(track: sourceTrack, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    frames.alwaysCopiesSampleData = false
    reader.add(frames)
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 360,
        AVVideoHeightKey: 640,
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 450_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 60
        ]
    ])
    video.expectsMediaDataInRealTime = false
    video.transform = sourceTrack.preferredTransform
    writer.add(video)
    guard writer.startWriting(), reader.startReading() else {
        throw writer.error ?? reader.error ?? NSError(domain: "Luciano", code: 2)
    }
    writer.startSession(atSourceTime: .zero)
    let done = DispatchSemaphore(value: 0)
    video.requestMediaDataWhenReady(on: DispatchQueue(label: "luciano.video.\(number)")) {
        while video.isReadyForMoreMediaData {
            if let frame = frames.copyNextSampleBuffer() {
                if !video.append(frame) {
                    reader.cancelReading()
                    video.markAsFinished()
                    done.signal()
                    return
                }
            } else {
                video.markAsFinished()
                writer.finishWriting { done.signal() }
                return
            }
        }
    }
    done.wait()
    guard writer.status == .completed, reader.status == .completed else {
        throw writer.error ?? reader.error ?? NSError(domain: "Luciano", code: 3)
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = NSSize(width: 360, height: 640)
    let image = try generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
    let bitmap = NSBitmapImageRep(cgImage: image)
    let poster = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.80])!
    try poster.write(to: output.appendingPathComponent("dino\(number)-poster.jpg"))
    let originalSize = try FileManager.default.attributesOfItem(atPath: input.path)[.size] as! Int
    let exportedSize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as! Int
    print("Dino\(number): \(originalSize) → \(exportedSize) bytes; MP4 sin audio + imagen fija.")
    fflush(stdout)
}
