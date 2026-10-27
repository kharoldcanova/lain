package com.lain.lain_mobile

import android.content.res.AssetManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

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
                else -> result.notImplemented()
            }
        }
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

    companion object {
        private const val MODEL_CHANNEL = "com.lain.lain_mobile/model"
        private const val BUFFER_SIZE = 1 shl 20
    }
}
