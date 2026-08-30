package com.example.punchin_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "workora/downloads"
        const val PDF_METHOD = "savePdfToDownloads"
        const val EXCEL_METHOD = "saveExcelToDownloads"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            if (call.method != PDF_METHOD && call.method != EXCEL_METHOD) {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val fileName = call.argument<String>("fileName")
                ?: if (call.method == PDF_METHOD) {
                    "attendance_report.pdf"
                } else {
                    "attendance_report.xlsx"
                }

            val bytes = call.argument<ByteArray>("bytes")

            if (bytes == null || bytes.isEmpty()) {
                result.error(
                    "INVALID_DATA",
                    "File data was empty.",
                    null
                )
                return@setMethodCallHandler
            }

            // The app targets modern Android devices. MediaStore is the
            // correct way to create a user-visible file in Downloads without
            // requesting broad storage permissions on Android 10+.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                result.error(
                    "UNSUPPORTED_ANDROID",
                    "Direct Downloads saving requires Android 10 or newer.",
                    null
                )
                return@setMethodCallHandler
            }

            val mimeType = if (call.method == PDF_METHOD) {
                "application/pdf"
            } else {
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            }

            try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(
                        MediaStore.Downloads.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/Workora"
                    )
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }

                val resolver = contentResolver

                val uri = resolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values
                )

                if (uri == null) {
                    result.error(
                        "SAVE_FAILED",
                        "Android could not create the file in Downloads/Workora.",
                        null
                    )
                    return@setMethodCallHandler
                }

                try {
                    resolver.openOutputStream(uri)?.use { output ->
                        output.write(bytes)
                        output.flush()
                    } ?: throw Exception(
                        "Android could not open the download file."
                    )

                    val completed = ContentValues().apply {
                        put(MediaStore.Downloads.IS_PENDING, 0)
                    }

                    resolver.update(
                        uri,
                        completed,
                        null,
                        null
                    )

                    result.success(
                        "Saved to Downloads/Workora/$fileName"
                    )
                } catch (e: Exception) {
                    // Remove a partially-created file if writing failed.
                    resolver.delete(uri, null, null)
                    throw e
                }

            } catch (e: Exception) {
                result.error(
                    "SAVE_FAILED",
                    e.message ?: "Could not save the file to Downloads/Workora.",
                    null
                )
            }
        }
    }
}
