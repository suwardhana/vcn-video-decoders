import CoreMedia
import Foundation
import VideoToolbox

var list: CFArray?
let status = VTCopyVideoEncoderList(nil, &list)
guard status == noErr, let encoders = list as? [[String: Any]] else {
  fputs("could not read the VideoToolbox encoder list (status \(status))\n", stderr)
  exit(1)
}
for encoder in encoders
where "\(encoder)".lowercased().contains("av1")
  || (encoder[kVTVideoEncoderList_CodecType as String] as? UInt32) == kCMVideoCodecType_AV1
{
  print(
    "encoder:",
    encoder[kVTVideoEncoderList_EncoderName as String] ?? "?",
    encoder[kVTVideoEncoderList_EncoderID as String] ?? "?"
  )
}
print("AV1 HW decode:", VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
