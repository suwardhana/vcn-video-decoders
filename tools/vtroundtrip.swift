// vtroundtrip: encode N synthetic frames with VideoToolbox, then decode them with a
// hardware-required VTDecompressionSession. Used to trace AppleGVA -> AMD VA driver calls.
// usage: vtroundtrip [codec=avc1|hvc1] [frames=30] [waitBeforeDecodeSeconds=0] [loops=1]
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

func fail(_ message: String) -> Never {
  fputs("vtroundtrip: \(message)\n", stderr)
  exit(1)
}

func positiveInt(_ text: String, name: String) -> Int {
  guard let value = Int(text), value > 0 else { fail("\(name) must be a positive integer") }
  return value
}

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
let codecName = args.count > 1 ? args[1] : "avc1"
guard ["avc1", "hvc1"].contains(codecName) else { fail("unsupported codec \(codecName)") }
let frameCount = args.count > 2 ? positiveInt(args[2], name: "frames") : 30
let waitSeconds = args.count > 3 ? Double(args[3]) : 0
guard let waitSeconds, waitSeconds >= 0, waitSeconds.isFinite else {
  fail("waitBeforeDecodeSeconds must be a finite non-negative number")
}
let loops = args.count > 4 ? positiveInt(args[4], name: "loops") : 1
let codec: CMVideoCodecType = codecName == "hvc1" ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
let width = 1920
let height = 1080

func makeFrame(_ i: Int) -> CVPixelBuffer? {
  var pb: CVPixelBuffer?
  let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
  let createStatus = CVPixelBufferCreate(
    nil,
    width,
    height,
    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    attrs as CFDictionary,
    &pb
  )
  guard createStatus == kCVReturnSuccess, let p = pb else { return nil }
  guard CVPixelBufferLockBaseAddress(p, []) == kCVReturnSuccess else { return nil }
  guard let yAddress = CVPixelBufferGetBaseAddressOfPlane(p, 0),
    let uvAddress = CVPixelBufferGetBaseAddressOfPlane(p, 1)
  else {
    CVPixelBufferUnlockBaseAddress(p, [])
    return nil
  }

  let y = yAddress.assumingMemoryBound(to: UInt8.self)
  let ys = CVPixelBufferGetBytesPerRowOfPlane(p, 0)
  for r in 0..<height {
    for c in 0..<width { y[r * ys + c] = UInt8(truncatingIfNeeded: (r + c + i * 8) & 0xff) }
  }
  let uv = uvAddress.assumingMemoryBound(to: UInt8.self)
  let uvs = CVPixelBufferGetBytesPerRowOfPlane(p, 1)
  for r in 0..<(height / 2) {
    for c in 0..<width { uv[r * uvs + c] = UInt8(truncatingIfNeeded: (r * 2 + i * 4) & 0xff) }
  }
  CVPixelBufferUnlockBaseAddress(p, [])
  return p
}

// Encode
var samples: [CMSampleBuffer] = []
var enc: VTCompressionSession?
let encoderStatus = VTCompressionSessionCreate(
  allocator: nil,
  width: Int32(width),
  height: Int32(height),
  codecType: codec,
  encoderSpecification: nil,
  imageBufferAttributes: nil,
  compressedDataAllocator: nil,
  outputCallback: nil,
  refcon: nil,
  compressionSessionOut: &enc
)
guard encoderStatus == noErr, let enc else { fail("encoder create (\(encoderStatus))") }
var propertyStatus = VTSessionSetProperty(
  enc,
  key: kVTCompressionPropertyKey_AllowFrameReordering,
  value: kCFBooleanFalse
)
guard propertyStatus == noErr else { fail("disable frame reordering (\(propertyStatus))") }
propertyStatus = VTSessionSetProperty(
  enc,
  key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
  value: 15 as CFNumber
)
guard propertyStatus == noErr else { fail("set keyframe interval (\(propertyStatus))") }
for i in 0..<frameCount {
  guard let frame = makeFrame(i) else { fail("pixel buffer creation failed for frame \(i)") }
  let pts = CMTime(value: CMTimeValue(i), timescale: 30)
  let encodeStatus = VTCompressionSessionEncodeFrame(
    enc,
    imageBuffer: frame,
    presentationTimeStamp: pts,
    duration: CMTime(value: 1, timescale: 30),
    frameProperties: nil,
    infoFlagsOut: nil
  ) { status, _, sb in if status == noErr, let sb { samples.append(sb) } }
  guard encodeStatus == noErr else { fail("encode frame \(i) (\(encodeStatus))") }
}
let completeStatus = VTCompressionSessionCompleteFrames(enc, untilPresentationTimeStamp: .invalid)
guard completeStatus == noErr else { fail("complete encoding (\(completeStatus))") }
guard !samples.isEmpty else { fail("encoder produced no samples") }
print("encoded \(samples.count) \(codecName) frames")

// Decode (hardware required)
guard let firstSample = samples.first, let fmt = CMSampleBufferGetFormatDescription(firstSample)
else { fail("missing encoded format description") }
let requireHardware = true
let spec: [CFString: Any] = [
  kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: requireHardware
]
let outAttrs: [CFString: Any] = [
  kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
  kCVPixelBufferIOSurfacePropertiesKey: [:],
]
var dec: VTDecompressionSession?
let decoderStatus = VTDecompressionSessionCreate(
  allocator: nil,
  formatDescription: fmt,
  decoderSpecification: spec as CFDictionary,
  imageBufferAttributes: outAttrs as CFDictionary,
  outputCallback: nil,
  decompressionSessionOut: &dec
)
guard decoderStatus == noErr, let dec else { fail("decoder create (\(decoderStatus))") }
var hw: CFBoolean?
VTSessionCopyProperty(
  dec,
  key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
  allocator: nil,
  valueOut: &hw
)
print(
  "decoder session created, hardware=\(hw.map { CFBooleanGetValue($0) } ?? false), pid \(getpid())"
)
if waitSeconds > 0 {
  print("waiting \(waitSeconds)s before decoding")
  Thread.sleep(forTimeInterval: waitSeconds)
}

for loop in 0..<loops {
  var ok = 0
  var bad = 0
  var firstChecksum = 0
  let t0 = Date()
  for (i, sb) in samples.enumerated() {
    let decodeStatus = VTDecompressionSessionDecodeFrame(
      dec,
      sampleBuffer: sb,
      flags: [],
      infoFlagsOut: nil
    ) { status, _, img, _, _ in
      if status == noErr, let img {
        ok += 1
        if i == 0 {
          if CVPixelBufferLockBaseAddress(img, .readOnly) == kCVReturnSuccess {
            if let yAddress = CVPixelBufferGetBaseAddressOfPlane(img, 0) {
              let y = yAddress.assumingMemoryBound(to: UInt8.self)
              firstChecksum = (0..<256).reduce(0) { acc, k in acc &+ Int(y[k * 7]) }
            } else {
              firstChecksum = -1
            }
            CVPixelBufferUnlockBaseAddress(img, .readOnly)
          } else {
            firstChecksum = -1
          }
        }
      } else {
        bad += 1
      }
    }
    if decodeStatus != noErr { bad += 1 }
  }
  let waitStatus = VTDecompressionSessionWaitForAsynchronousFrames(dec)
  guard waitStatus == noErr else { fail("wait for decoded frames (\(waitStatus))") }
  print(
    String(
      format: "loop %d: decoded ok=%d bad=%d in %.1f ms, frame0 checksum=%d",
      loop,
      ok,
      bad,
      Date().timeIntervalSince(t0) * 1000,
      firstChecksum
    )
  )
}
