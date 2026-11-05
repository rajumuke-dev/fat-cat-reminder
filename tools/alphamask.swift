import Vision
import AppKit
import CoreImage

// usage: alphamask <in_dir> <out_dir>   (cuts the foreground subject out of every PNG frame)
let inDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let files = try FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

let ctx = CIContext()
let lock = NSLock()
var minX = Int.max, minY = Int.max, maxX = 0, maxY = 0, failed = 0
var areas = [Int](repeating: 0, count: files.count)
var boxes = [(Int, Int, Int, Int)](repeating: (0, 0, 0, 0), count: files.count)

DispatchQueue.concurrentPerform(iterations: files.count) { i in
    do {
        let handler = VNImageRequestHandler(url: files[i])
        let req = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([req])
        guard let obs = req.results?.first else { lock.lock(); failed += 1; lock.unlock(); return }
        let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buf)
        let rep = NSBitmapImageRep(ciImage: ci)
        try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(files[i].lastPathComponent))
        // bounding box of non-transparent pixels, sampled on a coarse grid
        var x0 = Int.max, y0 = Int.max, x1 = 0, y1 = 0, area = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                area += 1; x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
            }
        }
        lock.lock(); areas[i] = area; boxes[i] = (x0, y0, x1, y1); lock.unlock()
    } catch { lock.lock(); failed += 1; lock.unlock(); FileHandle.standardError.write("\(files[i].lastPathComponent): \(error)\n".data(using: .utf8)!) }
}
// Vision sometimes grabs the whole background for a frame; replace such outliers with the nearest good frame
var bad = 0
for i in 0..<files.count {
    let near = (max(0, i - 8)...min(files.count - 1, i + 8)).map { areas[$0] }.sorted()
    let med = near[near.count / 2]
    func ok(_ a: Int) -> Bool { a * 100 <= med * 115 && a * 100 >= med * 85 }
    if !ok(areas[i]) {
        var good: Int? = nil
        var d = 1
        while good == nil && d < files.count {
            for j in [i - d, i + d] where good == nil && j >= 0 && j < files.count && ok(areas[j]) { good = j }
            d += 1
        }
        if let g = good {
            let dst = outDir.appendingPathComponent(files[i].lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: outDir.appendingPathComponent(files[g].lastPathComponent), to: dst)
            areas[i] = areas[g]; boxes[i] = boxes[g]; bad += 1
        }
    }
}
for b in boxes where b.2 > 0 { minX = min(minX, b.0); minY = min(minY, b.1); maxX = max(maxX, b.2); maxY = max(maxY, b.3) }
print("replaced \(bad) outlier frames")
print("frames \(files.count) failed \(failed) bbox x:\(minX)-\(maxX) y:\(minY)-\(maxY)")
