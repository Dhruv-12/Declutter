import CoreML
import Testing
import Vision
@testable import Declutter

/// Prints what Vision's feature print looks like on this machine, as recorded issues: the vector
/// length, its first values, and the distance between two very different images, for a request run
/// on the CPU from the start and for one retried on the CPU after the default device failed.
/// Disabled because it reports by failing; enable it by hand when Vision misbehaves on the simulator.
@Test(.disabled("Diagnostic: enable by hand to inspect Vision feature prints"))
func visionDiagnostic() throws {
    let cpu = MLComputeDevice.allComputeDevices.first { if case .cpu = $0 { return true }; return false }
    func print(_ image: CGImage, fresh: Bool) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        if fresh { request.setComputeDevice(cpu, for: .main) }
        else {
            _ = try? VNImageRequestHandler(cgImage: image).perform([request])
            request.setComputeDevice(cpu, for: .main)
        }
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.first
    }
    let a = Fixture.checkerboard(cell: 20, size: 300)
    let b = Fixture.image(width: 300, height: 300) { c in c.setFillColor(red: 1, green: 0.2, blue: 0.1, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 300, height: 300)) }
    for fresh in [true, false] {
        let pa = print(a, fresh: fresh), pb = print(b, fresh: fresh)
        var d: Float = -1
        if let pa, let pb { try? pa.computeDistance(&d, to: pb) }
        let head = pa.map { p in p.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(4)) } } ?? []
        Issue.record("DIAG fresh=\(fresh) count=\(pa?.elementCount ?? -1) head=\(head) distance=\(d)")
    }
}
