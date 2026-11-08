import VideoToolbox
import CoreMedia
var list: CFArray?
VTCopyVideoEncoderList(nil, &list)
for e in (list as! [[String: Any]]) where "\(e)".lowercased().contains("av1") || (e[kVTVideoEncoderList_CodecType as String] as? UInt32) == kCMVideoCodecType_AV1 {
  print("encoder:", e[kVTVideoEncoderList_EncoderName as String] ?? "?", e[kVTVideoEncoderList_EncoderID as String] ?? "?")
}
print("AV1 HW decode:", VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
