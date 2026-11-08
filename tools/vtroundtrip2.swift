// vtroundtrip: encode N synthetic frames with VideoToolbox, then decode them with a
// hardware-required VTDecompressionSession. Used to trace AppleGVA -> AMD VA driver calls.
// usage: vtroundtrip [codec=avc1|hvc1] [frames=30] [waitBeforeDecodeSeconds=0] [loops=1]
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
let codecName = args.count > 1 ? args[1] : "avc1"
let frameCount = args.count > 2 ? Int(args[2])! : 30
let waitSeconds = args.count > 3 ? Double(args[3])! : 0
let loops = args.count > 4 ? Int(args[4])! : 1
let codec: CMVideoCodecType = codecName == "hvc1" ? kCMVideoCodecType_HEVC : (codecName == "av01" ? kCMVideoCodecType_AV1 : kCMVideoCodecType_H264)
let width = 1920, height = 1080

func makeFrame(_ i: Int) -> CVPixelBuffer {
  var pb: CVPixelBuffer?
  let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
  CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attrs as CFDictionary, &pb)
  let p = pb!
  CVPixelBufferLockBaseAddress(p, [])
  let y = CVPixelBufferGetBaseAddressOfPlane(p, 0)!.assumingMemoryBound(to: UInt8.self)
  let ys = CVPixelBufferGetBytesPerRowOfPlane(p, 0)
  for r in 0..<height { for c in 0..<width { y[r * ys + c] = UInt8(truncatingIfNeeded: (r + c + i * 8) & 0xff) } }
  let uv = CVPixelBufferGetBaseAddressOfPlane(p, 1)!.assumingMemoryBound(to: UInt8.self)
  let uvs = CVPixelBufferGetBytesPerRowOfPlane(p, 1)
  for r in 0..<(height / 2) { for c in 0..<width { uv[r * uvs + c] = UInt8(truncatingIfNeeded: (r * 2 + i * 4) & 0xff) } }
  CVPixelBufferUnlockBaseAddress(p, [])
  return p
}

// Encode
var samples: [CMSampleBuffer] = []
var enc: VTCompressionSession?
var st = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height), codecType: codec,
  encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
  outputCallback: nil, refcon: nil, compressionSessionOut: &enc)
print("encoder create status", st); if st != noErr { exit(1) }
VTSessionSetProperty(enc!, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
VTSessionSetProperty(enc!, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 15 as CFNumber)
for i in 0..<frameCount {
  let pts = CMTime(value: CMTimeValue(i), timescale: 30)
  VTCompressionSessionEncodeFrame(enc!, imageBuffer: makeFrame(i), presentationTimeStamp: pts, duration: CMTime(value: 1, timescale: 30),
    frameProperties: nil, infoFlagsOut: nil) { status, _, sb in
      if status == noErr, let sb { samples.append(sb) }
  }
}
VTCompressionSessionCompleteFrames(enc!, untilPresentationTimeStamp: .invalid)
print("encoded \(samples.count) \(codecName) frames")

// Decode (hardware required)
let fmt = CMSampleBufferGetFormatDescription(samples[0])!
let spec: [CFString: Any] = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: ProcessInfo.processInfo.environment["SW"] == nil]
let outAttrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                 kCVPixelBufferIOSurfacePropertiesKey: [:]]
var dec: VTDecompressionSession?
st = VTDecompressionSessionCreate(allocator: nil, formatDescription: fmt, decoderSpecification: spec as CFDictionary,
  imageBufferAttributes: outAttrs as CFDictionary, outputCallback: nil, decompressionSessionOut: &dec)
precondition(st == noErr, "decoder create \(st)")
var hw: CFBoolean?
VTSessionCopyProperty(dec!, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, allocator: nil, valueOut: &hw)
print("decoder session created, hardware=\(hw.map { CFBooleanGetValue($0) } ?? false), pid \(getpid())")
if waitSeconds > 0 { print("waiting \(waitSeconds)s before decoding"); Thread.sleep(forTimeInterval: waitSeconds) }

for loop in 0..<loops {
  var ok = 0, bad = 0
  var firstChecksum = 0
  let t0 = Date()
  for (i, sb) in samples.enumerated() {
    VTDecompressionSessionDecodeFrame(dec!, sampleBuffer: sb, flags: [], infoFlagsOut: nil) { status, _, img, _, _ in
      if status == noErr, let img {
        ok += 1
        if i == 0 {
          CVPixelBufferLockBaseAddress(img, .readOnly)
          let y = CVPixelBufferGetBaseAddressOfPlane(img, 0)!.assumingMemoryBound(to: UInt8.self)
          firstChecksum = (0..<256).reduce(0) { acc, k in acc &+ Int(y[k * 7]) }
          CVPixelBufferUnlockBaseAddress(img, .readOnly)
        }
      } else { bad += 1 }
    }
  }
  VTDecompressionSessionWaitForAsynchronousFrames(dec!)
  print(String(format: "loop %d: decoded ok=%d bad=%d in %.1f ms, frame0 checksum=%d", loop, ok, bad, Date().timeIntervalSince(t0) * 1000, firstChecksum))
}
