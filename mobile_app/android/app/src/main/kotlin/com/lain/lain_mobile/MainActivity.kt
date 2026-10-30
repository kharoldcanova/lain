package com.lain.lain_mobile

import android.content.Intent
import android.content.res.AssetManager
import android.net.Uri
import android.os.StatFs
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingImport: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MODEL_CHANNEL)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "copyAsset" -> {
                    val asset = call.argument<String>("asset")
                    val target = call.argument<String>("target")
                    if (asset == null || target == null) {
                        result.error("bad_args", "faltan asset o target", null)
                        return@setMethodCallHandler
                    }
                    copyAsset(asset, target, result)
                }
                "freeBytes" -> {
                    try {
                        result.success(StatFs(filesDir.path).availableBytes)
                    } catch (error: Throwable) {
                        result.error("stat_failed", error.message ?: error.toString(), null)
                    }
                }
                "pickAndImport" -> {
                    val targetDir = call.argument<String>("targetDir")
                    if (targetDir == null || pendingImport != null) {
                        result.error("bad_args", "faltan argumentos o ya hay una importación en curso", null)
                        return@setMethodCallHandler
                    }
                    pendingImport = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(
                        Intent.createChooser(intent, "Elegí un modelo .gguf"), PICK_MODEL_REQUEST)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_MODEL_REQUEST) return
        val result = pendingImport ?: return
        pendingImport = null
        val targetDir = data?.let { lastTargetDir } ?: return
        if (resultCode != RESULT_OK || data == null || data.data == null) {
            result.error("pick_cancelled", "selección cancelada", null)
            return
        }
        copyUri(data.data!!, targetDir, result)
    }

    private fun resolveName(uri: Uri): String {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                } ?: "modelo.gguf"
        } catch (error: Throwable) {
            "modelo.gguf"
        }
    }

    /** Copia el archivo elegido con SAF a `targetDir/<nombre>` usando `.part` + renombrado. */
    private fun copyUri(uri: Uri, targetDir: String, result: MethodChannel.Result) {
        Thread {
            val name = resolveName(uri).replace(Regex("[^A-Za-z0-9._-]"), "_")
            val tmp = File("$targetDir/$name.part")
            val dest = File("$targetDir/$name")
            try {
                File(targetDir).mkdirs()
                val input = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("no se pudo abrir el archivo elegido")
                input.use { stream ->
                    FileOutputStream(tmp).use { output ->
                        stream.copyTo(output, BUFFER_SIZE)
                        output.fd.sync()
                    }
                }
                if (dest.exists()) dest.delete()
                if (!tmp.renameTo(dest)) {
                    throw IllegalStateException("no se pudo mover el modelo a $dest")
                }
                postResult { result.success(dest.absolutePath) }
            } catch (error: Throwable) {
                tmp.delete()
                postResult { result.error("import_failed", error.message ?: error.toString(), null) }
            }
        }.start()
    }

    /** Copia el GGUF empaquetado a `target` reportando progreso 0..1 por el canal. */
    private fun copyAsset(asset: String, target: String, result: MethodChannel.Result) {
        Thread {
            val tmp = File("$target.part")
            try {
                val total = assets.openFd(asset).use { it.length }
                tmp.parentFile?.mkdirs()
                val buffer = ByteArray(BUFFER_SIZE)
                var copied = 0L
                var lastPercent = -1

                assets.open(asset, AssetManager.ACCESS_STREAMING).use { input ->
                    FileOutputStream(tmp).use { output ->
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            copied += read
                            val percent = if (total > 0) ((copied * 100) / total).toInt() else -1
                            if (percent != lastPercent) {
                                lastPercent = percent
                                reportProgress(percent / 100.0)
                            }
                        }
                        output.fd.sync()
                    }
                }

                val dest = File(target)
                if (dest.exists()) dest.delete()
                if (!tmp.renameTo(dest)) {
                    throw IllegalStateException("no se pudo mover el modelo a $target")
                }
                postResult { result.success(dest.absolutePath) }
            } catch (error: Throwable) {
                tmp.delete()
                postResult { result.error("copy_failed", error.message ?: error.toString(), null) }
            }
        }.start()
    }

    private fun reportProgress(progress: Double) {
        postResult { channel?.invokeMethod("progress", mapOf("progress" to progress)) }
    }

    private fun postResult(block: () -> Unit) {
        runOnUiThread(block)
    }

    private val lastTargetDir: String?
        get() = _lastTargetDir

    private var _lastTargetDir: String? = null

    companion object {
        private const val MODEL_CHANNEL = "com.lain.lain_mobile/model"
        private const val BUFFER_SIZE = 1 shl 20
        private const val PICK_MODEL_REQUEST = 1001
    }
}
