import Foundation
import Vision

@main
struct StickerErrorSmoke {
    static func main() {
        let inferenceError = NSError(domain: VNErrorDomain, code: 9)
        precondition(StickerProcessor.classify(inferenceError, isSimulator: true) == .simulatorUnavailable)
        precondition(!StickerProcessor.classify(inferenceError, isSimulator: true).canRetry)
        precondition(StickerProcessor.classify(inferenceError, isSimulator: false) == .processingFailed)
        precondition(StickerProcessor.classify(StickerProcessor.ProcessingError.noSubject, isSimulator: true) == .noSubject)
        precondition(StickerProcessor.classify(NSError(domain: NSCocoaErrorDomain, code: 9), isSimulator: true) == .processingFailed)
        print("PASS: simulator inference failure is distinct from no subject, encoding failure, and device errors")
    }
}
