// Puente C entre Dart y whisper.cpp para el dictado local de LAIN.
//
// El modelo se carga una vez y se reutiliza entre transcripciones. La entrada
// es PCM float mono a 16 kHz; la salida es texto UTF-8 sin timestamps.
//
// Solo se exportan las funciones `lain_stt_*` (ver el version script del build)
// para no chocar con los símbolos ggml de liblain_llm.so en el mismo proceso.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "whisper.h"

#if defined(_WIN32)
#define LAIN_EXPORT __declspec(dllexport)
#else
#define LAIN_EXPORT __attribute__((visibility("default")))
#endif

typedef struct {
    struct whisper_context *ctx;
    int threads;
} lain_stt_handle;

static void lain_stt_set_error(char *err, int err_len, const char *message) {
    if (err == NULL || err_len <= 0) return;
    snprintf(err, (size_t) err_len, "%s", message);
}

LAIN_EXPORT intptr_t lain_stt_load(
    const char *model_path,
    int threads,
    char *err,
    int err_len) {
    if (model_path == NULL || model_path[0] == '\0') {
        lain_stt_set_error(err, err_len, "falta la ruta del modelo Whisper");
        return 0;
    }

    struct whisper_context_params params = whisper_context_default_params();
    struct whisper_context *ctx = whisper_init_from_file_with_params(model_path, params);
    if (ctx == NULL) {
        lain_stt_set_error(err, err_len, "no se pudo cargar el modelo Whisper");
        return 0;
    }

    lain_stt_handle *handle = (lain_stt_handle *) calloc(1, sizeof(lain_stt_handle));
    if (handle == NULL) {
        whisper_free(ctx);
        lain_stt_set_error(err, err_len, "sin memoria para el motor de voz");
        return 0;
    }
    handle->ctx = ctx;
    handle->threads = threads > 0 ? threads : 4;
    return (intptr_t) handle;
}

LAIN_EXPORT void lain_stt_free(intptr_t handle_ptr) {
    lain_stt_handle *handle = (lain_stt_handle *) handle_ptr;
    if (handle == NULL) return;
    if (handle->ctx != NULL) whisper_free(handle->ctx);
    free(handle);
}

/// Transcribe [n_samples] muestras float mono a 16 kHz.
///
/// Devuelve el número de bytes escritos en [out] (sin contar el NUL final),
/// o -1 si falla. El texto puede quedar vacío si no se detecta habla.
LAIN_EXPORT int lain_stt_transcribe(
    intptr_t handle_ptr,
    const float *samples,
    int n_samples,
    const char *language,
    char *out,
    int out_len,
    char *err,
    int err_len) {
    lain_stt_handle *handle = (lain_stt_handle *) handle_ptr;
    if (handle == NULL || handle->ctx == NULL) {
        lain_stt_set_error(err, err_len, "el motor de voz no está cargado");
        return -1;
    }
    if (samples == NULL || n_samples <= 0) {
        lain_stt_set_error(err, err_len, "no hay audio para transcribir");
        return -1;
    }
    if (out == NULL || out_len <= 0) {
        lain_stt_set_error(err, err_len, "falta el búfer de salida");
        return -1;
    }
    out[0] = '\0';

    struct whisper_full_params params =
        whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = handle->threads;
    params.translate = false;
    params.no_context = true;
    params.no_timestamps = true;
    params.single_segment = false;
    params.print_special = false;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.language = (language != NULL && language[0] != '\0') ? language : "es";
    params.detect_language = false;

    if (whisper_full(handle->ctx, params, samples, n_samples) != 0) {
        lain_stt_set_error(err, err_len, "la transcripción falló");
        return -1;
    }

    const int segments = whisper_full_n_segments(handle->ctx);
    size_t used = 0;
    for (int i = 0; i < segments; i++) {
        const char *text = whisper_full_get_segment_text(handle->ctx, i);
        if (text == NULL) continue;
        while (*text == ' ') text++;
        if (*text == '\0') continue;

        if (used > 0 && used + 1 < (size_t) out_len) {
            out[used++] = ' ';
        }
        const size_t remaining = (size_t) out_len - used - 1;
        const size_t length = strlen(text);
        const size_t take = length < remaining ? length : remaining;
        memcpy(out + used, text, take);
        used += take;
        if (take < length) break; // el búfer se llenó
    }
    out[used] = '\0';
    return (int) used;
}
