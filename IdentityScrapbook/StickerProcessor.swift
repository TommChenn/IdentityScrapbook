import Foundation
import Vision
import CoreImage
import OSLog

nonisolated enum StickerProcessor {
    enum ProcessingError: Error {
        case noSubject, encodingFailed, simulatorUnavailable, processingFailed

        var canRetry: Bool { self != .simulatorUnavailable }
    }

    static func classify(_ error: Error, isSimulator: Bool) -> ProcessingError {
        if let error = error as? ProcessingError { return error }
        let underlying = error as NSError
        if isSimulator && underlying.domain == VNErrorDomain && underlying.code == 9 {
            return .simulatorUnavailable
        }
        return .processingFailed
    }

    static func cutout(_ original: Data) throws -> Data {
        do { return try performCutout(original) }
        catch is CancellationError { throw CancellationError() }
        catch {
            let diagnostic = error as NSError
            Logger(subsystem: "app.chen.tom.IdentityScrapbook", category: "StickerProcessing")
                .error("Cutout failed: domain=\(diagnostic.domain, privacy: .public) code=\(diagnostic.code)")
            #if targetEnvironment(simulator)
            throw classify(error, isSimulator: true)
            #else
            throw classify(error, isSimulator: false)
            #endif
        }
    }

    private static func performCutout(_ original: Data) throws -> Data {
        try Task.checkCancellation()
        // Normalize orientation and bound processing memory; keep the original untouched.
        let input = try PhotoFiles.preview(original, maxPixels: 2048)
        let handler = VNImageRequestHandler(data: input, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        try Task.checkCancellation()
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ProcessingError.noSubject
        }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances,
                                                         from: handler, croppedToInstancesExtent: true)
        let image = CIImage(cvPixelBuffer: buffer)
        guard let png = CIContext().pngRepresentation(of: image, format: .RGBA8,
                                                       colorSpace: CGColorSpaceCreateDeviceRGB()) else {
            throw ProcessingError.encodingFailed
        }
        try Task.checkCancellation()
        return png
    }
}
