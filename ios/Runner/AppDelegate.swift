import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let cameraChannel = FlutterMethodChannel(name: "com.example.misa/camera",
                                              binaryMessenger: controller.binaryMessenger)
    cameraChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "compressFrame" {
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int,
              let bytesPerRow = args["bytesPerRow"] as? Int,
              let targetWidth = args["targetWidth"] as? Int else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
        }

        let data = bytes.data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let dataProvider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bitsPerPixel: 32,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo,
                                    provider: dataProvider,
                                    decode: nil,
                                    shouldInterpolate: true,
                                    intent: .defaultIntent) else {
          result(FlutterError(code: "IMAGE_ERROR", message: "Failed to create CGImage", details: nil))
          return
        }

        let uiImage = UIImage(cgImage: cgImage)
        
        let targetSize = CGSize(width: targetWidth, height: Int(CGFloat(height) * (CGFloat(targetWidth) / CGFloat(width))))
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        if let finalImage = resizedImage, let jpegData = finalImage.jpegData(compressionQuality: 0.6) {
          result(FlutterStandardTypedData(bytes: jpegData))
        } else {
          result(FlutterError(code: "COMPRESSION_ERROR", message: "Failed to compress to JPEG", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
