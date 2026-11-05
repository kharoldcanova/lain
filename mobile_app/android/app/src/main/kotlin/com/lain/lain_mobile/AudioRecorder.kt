package com.lain.lain_mobile

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.io.ByteArrayOutputStream

/**
 * Graba PCM16 mono a 16 kHz, el formato que consume whisper.cpp.
 *
 * Se ejecuta en un hilo propio: `stop()` espera a que el hilo cierre el
 * `AudioRecord` antes de devolver las muestras. Nunca deja el micrófono
 * abierto si el usuario cancela.
 */
class AudioRecorder {
    private var record: AudioRecord? = null
    private var thread: Thread? = null

    @Volatile
    private var running = false

    @Volatile
    private var failure: String? = null

    private val output = ByteArrayOutputStream()

    val isRecording: Boolean
        get() = running

    fun start() {
        if (running) return
        val minimum = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING)
        if (minimum <= 0) {
            throw IllegalStateException("el micrófono no soporta 16 kHz mono")
        }
        val bufferSize = maxOf(minimum, SAMPLE_RATE / 2)
        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                CHANNEL,
                ENCODING,
                bufferSize * 2,
            )
        } catch (error: Throwable) {
            throw IllegalStateException("no se pudo crear el micrófono: ${error.message}")
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            throw IllegalStateException("el micrófono no está disponible")
        }

        synchronized(output) { output.reset() }
        failure = null
        record = recorder
        running = true
        try {
            recorder.startRecording()
        } catch (error: Throwable) {
            running = false
            record = null
            recorder.release()
            throw IllegalStateException("no se pudo iniciar la grabación: ${error.message}")
        }

        thread = Thread {
            val buffer = ByteArray(bufferSize)
            try {
                while (running) {
                    val read = recorder.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        synchronized(output) { output.write(buffer, 0, read) }
                    } else if (read < 0) {
                        failure = "la lectura del micrófono falló ($read)"
                        break
                    }
                }
            } catch (error: Throwable) {
                failure = error.message ?: error.toString()
            }
        }.also { it.start() }
    }

    /** Detiene la grabación y devuelve PCM16 little-endian. */
    fun stop(): ByteArray {
        if (!running && record == null) return ByteArray(0)
        running = false
        thread?.join(1500)
        thread = null
        val recorder = record
        record = null
        try {
            recorder?.stop()
        } catch (_: Throwable) {
            // El hilo pudo cerrarlo; no es un error del usuario.
        }
        recorder?.release()
        failure?.let { message ->
            failure = null
            synchronized(output) { output.reset() }
            throw IllegalStateException(message)
        }
        val samples = synchronized(output) { output.toByteArray() }
        synchronized(output) { output.reset() }
        return samples
    }

    /** Descarta la grabación en curso sin devolver muestras. */
    fun cancel() {
        running = false
        thread?.join(1000)
        thread = null
        val recorder = record
        record = null
        try {
            recorder?.stop()
        } catch (_: Throwable) {
            // Sin grabación activa.
        }
        recorder?.release()
        failure = null
        synchronized(output) { output.reset() }
    }

    companion object {
        const val SAMPLE_RATE = 16000
        private const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
    }
}
