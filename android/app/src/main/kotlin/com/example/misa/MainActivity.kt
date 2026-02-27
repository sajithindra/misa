package com.example.misa

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.misa/camera"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "compressFrame") {
                try {
                    val arguments = call.arguments as Map<*, *>
                    val planes = arguments["planes"] as List<Map<*, *>>
                    val width = arguments["width"] as Int
                    val height = arguments["height"] as Int
                    val targetWidth = arguments["targetWidth"] as Int

                    val yPlane = planes[0]["bytes"] as ByteArray
                    val uPlane = planes[1]["bytes"] as ByteArray
                    val vPlane = planes[2]["bytes"] as ByteArray

                    val yRowStride = planes[0]["bytesPerRow"] as Int
                    val uvRowStride = planes[1]["bytesPerRow"] as Int
                    val uvPixelStride = planes[1]["bytesPerPixel"] as Int

                    // Convert to NV21
                    val nv21 = ByteArray(width * height + 2 * (width / 2) * (height / 2))
                    var offset = 0

                    if (yRowStride == width) {
                        System.arraycopy(yPlane, 0, nv21, 0, yPlane.size)
                        offset = yPlane.size
                    } else {
                        var yPos = 0
                        for (r in 0 until height) {
                            System.arraycopy(yPlane, yPos, nv21, offset, width)
                            yPos += yRowStride
                            offset += width
                        }
                    }

                    val halfWidth = width / 2
                    val halfHeight = height / 2
                    for (r in 0 until halfHeight) {
                        val rowOffset = r * uvRowStride
                        for (c in 0 until halfWidth) {
                            val pixelOffset = rowOffset + c * uvPixelStride
                            if (pixelOffset < vPlane.size && pixelOffset < uPlane.size) {
                                nv21[offset++] = vPlane[pixelOffset]
                                nv21[offset++] = uPlane[pixelOffset]
                            }
                        }
                    }

                    // Compress to JPEG
                    val yuvImage = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                    var out = ByteArrayOutputStream()
                    yuvImage.compressToJpeg(Rect(0, 0, width, height), 60, out)
                    var jpegBytes = out.toByteArray()

                    if (width > targetWidth) {
                        val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                        val scale = targetWidth.toFloat() / bitmap.width
                        val scaledHeight = (bitmap.height * scale).toInt()
                        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, targetWidth, scaledHeight, true)
                        out = ByteArrayOutputStream()
                        scaledBitmap.compress(Bitmap.CompressFormat.JPEG, 60, out)
                        jpegBytes = out.toByteArray()
                        bitmap.recycle()
                        scaledBitmap.recycle()
                    }

                    result.success(jpegBytes)
                } catch (e: Exception) {
                    result.error("COMPRESSION_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
