package com.bytebox.app

import android.app.Activity
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val upiRequest = 4242
    private val pickRequest = 4343
    private var upiResult: MethodChannel.Result? = null
    private var pickResult: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ---------------- UPI ----------------
        MethodChannel(messenger, "app/upi").setMethodCallHandler { call, result ->
            when (call.method) {
                "pay" -> startUpi(call.argument<String>("uri") ?: "", result)
                else -> result.notImplemented()
            }
        }

        // ---------------- Native helpers ----------------
        MethodChannel(messenger, "app/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> pickFile(call.argument<String>("mime") ?: "*/*", result)
                "videoInfo" -> background(result) { videoInfo(call.argument<String>("path")!!) }
                "download" -> background(result) {
                    download(call.argument<String>("url")!!, call.argument<String>("fileName")!!,
                        call.argument<String>("title") ?: "Bytebox")
                }
                "share" -> {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                    }
                    startActivity(Intent.createChooser(send, call.argument<String>("title") ?: "Share"))
                    result.success(true)
                }
                "openFile" -> openFile(call.argument<String>("path")!!, call.argument<String>("mime"), result)
                "deviceInfo" -> result.success(
                    mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "sdk" to Build.VERSION.SDK_INT,
                        "package" to packageName,
                    )
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { result.error("NATIVE_ERROR", e.message, null) }
            }
        }
    }

    /**
     * Opens the UPI intent. The list of resolvers only decides chooser vs direct launch:
     * many OEM ROMs (MIUI, ColorOS, Vivo) return an empty list even when UPI apps exist,
     * so "no UPI app" is reported ONLY when the launch itself throws.
     */
    private fun startUpi(uri: String, result: MethodChannel.Result) {
        if (upiResult != null) {
            result.error("BUSY", "A payment is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        val resolvers = try {
            packageManager.queryIntentActivities(intent, 0)
        } catch (e: Exception) {
            emptyList()
        }
        val launch = if (resolvers.size == 1) intent else Intent.createChooser(intent, "Pay with")
        upiResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(launch, upiRequest)
        } catch (e: ActivityNotFoundException) {
            upiResult = null
            result.error("NO_UPI_APP", "No UPI app found", null)
        } catch (e: Exception) {
            upiResult = null
            result.error("UPI_ERROR", e.message, null)
        }
    }

    private fun pickFile(mime: String, result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("BUSY", "Picker already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            if (mime.contains(",")) {
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, mime.split(",").map { it.trim() }.toTypedArray())
            }
        }
        pickResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, pickRequest)
        } catch (e: Exception) {
            pickResult = null
            result.error("PICK_ERROR", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            upiRequest -> {
                val r = upiResult ?: return
                upiResult = null
                // UPI apps return "response" (some also "Status"/"txnId" extras). Empty = back / not completed.
                val extras = data?.extras
                val response = data?.getStringExtra("response")
                    ?: extras?.keySet()?.joinToString("&") { "$it=${extras.get(it) ?: ""}" }
                    ?: ""
                r.success(response)
            }
            pickRequest -> {
                val r = pickResult ?: return
                pickResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    r.success(null)
                    return
                }
                io.execute {
                    try {
                        val info = copyToCache(uri)
                        runOnUiThread { r.success(info) }
                    } catch (e: Exception) {
                        runOnUiThread { r.error("PICK_ERROR", e.message, null) }
                    }
                }
            }
        }
    }

    private fun copyToCache(uri: Uri): Map<String, Any?> {
        var name = "file"
        var size = -1L
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val s = c.getColumnIndex(OpenableColumns.SIZE)
                if (n >= 0) name = c.getString(n) ?: name
                if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
            }
        }
        val mime = contentResolver.getType(uri) ?: "application/octet-stream"
        val dir = File(cacheDir, "picked").apply { mkdirs() }
        val out = File(dir, UUID.randomUUID().toString() + "_" + name.replace(Regex("[^A-Za-z0-9._-]"), "_"))
        contentResolver.openInputStream(uri)!!.use { input -> FileOutputStream(out).use { input.copyTo(it) } }
        return mapOf("path" to out.absolutePath, "name" to name, "size" to out.length(), "mime" to mime)
    }

    private fun videoInfo(path: String): Map<String, Any?> {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            val duration = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val frame = r.getFrameAtTime(minOf(1_000_000L, duration * 500L), MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            var thumb: String? = null
            if (frame != null) {
                val scale = 720f / maxOf(frame.width, 1)
                val scaled = if (scale < 1f) Bitmap.createScaledBitmap(
                    frame, 720, (frame.height * scale).toInt().coerceAtLeast(1), true) else frame
                val out = File(cacheDir, "thumb_" + UUID.randomUUID() + ".jpg")
                FileOutputStream(out).use { scaled.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                thumb = out.absolutePath
            }
            return mapOf("durationMs" to duration, "thumbnail" to thumb)
        } finally {
            r.release()
        }
    }

    private fun download(url: String, fileName: String, title: String): Long {
        val req = DownloadManager.Request(Uri.parse(url))
            .setTitle(title)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Bytebox/$fileName")
        val dm = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        return dm.enqueue(req)
    }

    private fun openFile(path: String, mime: String?, result: MethodChannel.Result) {
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.files", File(path))
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime ?: contentResolver.getType(uri) ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(view, "Open with"))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("NO_APP", "No app can open this file", null)
        } catch (e: Exception) {
            result.error("OPEN_ERROR", e.message, null)
        }
    }
}
