package com.lain.lain_mobile

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * Envuelve el TTS nativo de Android.
 *
 * `speak` usa `QUEUE_ADD` para que las oraciones se reproduzcan en orden sin
 * cortarse entre sí. El primer `speak` de cada turno limpia la cola.
 */
class TtsPlayer(
    context: Context,
    private val onEvent: (String, String?) -> Unit,
) {
    private var engine: TextToSpeech? = null
    private var ready = false

    init {
        engine = TextToSpeech(context.applicationContext) { status ->
            if (status != TextToSpeech.SUCCESS) {
                onEvent("unavailable", null)
                return@TextToSpeech
            }
            val tts = engine ?: return@TextToSpeech
            val spanish = Locale("es", "ES")
            val result = tts.setLanguage(spanish)
            if (result == TextToSpeech.LANG_MISSING_DATA ||
                result == TextToSpeech.LANG_NOT_SUPPORTED
            ) {
                tts.setLanguage(Locale.getDefault())
            }
            tts.setSpeechRate(1.0f)
            tts.setPitch(1.0f)
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = onEvent("start", utteranceId)
                override fun onDone(utteranceId: String?) = onEvent("done", utteranceId)

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = onEvent("error", utteranceId)

                override fun onError(utteranceId: String?, errorCode: Int) =
                    onEvent("error", utteranceId)
            })
            ready = true
            onEvent("ready", null)
        }
    }

    fun isReady(): Boolean = ready

    fun speak(text: String, utteranceId: String, flush: Boolean): Boolean {
        val tts = engine ?: return false
        if (!ready) return false
        val mode = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        return tts.speak(text, mode, null, utteranceId) == TextToSpeech.SUCCESS
    }

    fun stop() {
        engine?.stop()
    }

    fun shutdown() {
        ready = false
        engine?.stop()
        engine?.shutdown()
        engine = null
    }
}
