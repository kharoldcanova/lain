// Puente C mínimo entre Dart (dart:ffi) y llama.cpp para Android.
// Expose solo lo que la app necesita: cargar el GGUF, formatear el turno con la
// plantilla del modelo y generar texto emitiendo cada pieza por callback.
//
// VARIANTE EXPERIMENTAL: carga dinámica de las variantes del backend CPU
// (libggml-cpu-android_*.so) antes de llama_backend_init(). No se usa en el
// puente de producción, que linkea estáticamente libggml-cpu.
#include <dlfcn.h>
#include <libgen.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "ggml-backend.h"
#include "llama.h"

typedef void (*lain_piece_cb)(const char * piece, int32_t len, void * user_data);

// Copia de las métricas del último turno. El layout debe coincidir con la
// struct `LainMetrics` de Dart (4 int64 + 8 int32 = 64 bytes).
typedef struct {
    int64_t load_ms;
    int64_t prefill_ms;
    int64_t decode_ms;
    int64_t ttft_ms;
    int32_t n_prompt_tokens;
    int32_t n_generated_tokens;
    int32_t n_threads;
    int32_t n_batch_threads;
    int32_t n_ctx;
    int32_t load_mode;
    int32_t n_backend;
    int32_t instrumented;
} lain_metrics;

typedef struct {
    struct llama_model * model;
    struct llama_context * ctx;
    const struct llama_vocab * vocab;
    int32_t n_ctx;
    int64_t load_ms;
    int32_t load_mode;
    lain_metrics last;
} lain_session;

static int64_t lain_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t) ts.tv_sec * 1000 + (int64_t) ts.tv_nsec / 1000000;
}

// ---------------------------------------------------------------------------
// Carga dinámica de backends
// ---------------------------------------------------------------------------

static pthread_mutex_t g_backend_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool g_backend_ready = false;
static bool g_llama_backend_ready = false;
static char g_backend_dir[1024];
static char g_backend_error[512];

static void lain_set_error(char * err, int32_t err_len, const char * msg) {
    if (err == NULL || err_len <= 0) {
        return;
    }
    snprintf(err, (size_t) err_len, "%s", msg);
}

// Inicializa backends y llama_backend_init() una sola vez, en ese orden.
// Devuelve NULL si quedó listo o un mensaje de error (sin fallback silencioso).
// Nunca deja el estado a medias: si falla, el siguiente intento vuelve a probar.
static const char * lain_ensure_backends(void) {
    pthread_mutex_lock(&g_backend_mutex);

    if (g_backend_ready && g_llama_backend_ready) {
        pthread_mutex_unlock(&g_backend_mutex);
        return NULL;
    }

    if (!g_backend_ready) {
        g_backend_dir[0] = '\0';
        if (ggml_backend_reg_count() == 0) {
            Dl_info info;
            if (dladdr((void *) &ggml_backend_reg_count, &info) == 0 ||
                info.dli_fname == NULL || info.dli_fname[0] == '\0') {
                snprintf(g_backend_error, sizeof(g_backend_error),
                         "no se pudo localizar libggml.so con dladdr; "
                         "no se pueden cargar las variantes del backend CPU");
                pthread_mutex_unlock(&g_backend_mutex);
                return g_backend_error;
            }
            char path_copy[1024];
            snprintf(path_copy, sizeof(path_copy), "%s", info.dli_fname);
            const char * dir = dirname(path_copy);
            if (dir == NULL || dir[0] != '/') {
                snprintf(g_backend_error, sizeof(g_backend_error),
                         "ruta de backend no absoluta: %s", info.dli_fname);
                pthread_mutex_unlock(&g_backend_mutex);
                return g_backend_error;
            }
            snprintf(g_backend_dir, sizeof(g_backend_dir), "%s", dir);

            ggml_backend_load_all_from_path(g_backend_dir);

            if (ggml_backend_reg_count() == 0) {
                snprintf(g_backend_error, sizeof(g_backend_error),
                         "no hay backends GGML registrados en %s; "
                         "verificá que las libggml-cpu-*.so estén extraídas "
                         "del APK (useLegacyPackaging)", g_backend_dir);
                pthread_mutex_unlock(&g_backend_mutex);
                return g_backend_error;
            }
        }
        g_backend_ready = true;
    }

    if (!g_llama_backend_ready) {
        llama_backend_init();
        g_llama_backend_ready = true;
    }

    pthread_mutex_unlock(&g_backend_mutex);
    return NULL;
}

// Nombre del archivo de la variante realmente cargada (p. ej.
// "libggml-cpu-android_armv8.2_2.so"), o -1 si no se puede identificar.
// Se obtiene del módulo que contiene la función del backend, no del conteo de
// registros: un registro puede existir sin ser el que ejecuta la inferencia.
int32_t lain_backend_name(char * out, int32_t out_len) {
    if (out == NULL || out_len <= 0) {
        return -1;
    }
    out[0] = '\0';
    const size_t count = ggml_backend_reg_count();
    for (size_t i = 0; i < count; i++) {
        ggml_backend_reg_t reg = ggml_backend_reg_get(i);
        if (reg == NULL) {
            continue;
        }
        void * proc = ggml_backend_reg_get_proc_address(reg, "ggml_backend_get_features");
        if (proc == NULL) {
            proc = ggml_backend_reg_get_proc_address(reg, "ggml_backend_set_n_threads");
        }
        if (proc == NULL) {
            continue;
        }
        Dl_info info;
        if (dladdr(proc, &info) == 0 || info.dli_fname == NULL) {
            continue;
        }
        const char * base = strrchr(info.dli_fname, '/');
        base = base != NULL ? base + 1 : info.dli_fname;
        snprintf(out, (size_t) out_len, "%s", base);
        return (int32_t) strlen(out);
    }
    return -1;
}


static int32_t lain_tokenize(const struct llama_vocab * vocab, const char * text,
                             llama_token ** out) {
    const int32_t len = (int32_t) strlen(text);
    int32_t needed = llama_tokenize(vocab, text, len, NULL, 0, true, true);
    if (needed < 0) {
        needed = -needed;
    }
    if (needed == 0) {
        *out = NULL;
        return 0;
    }

    llama_token * tokens = (llama_token *) malloc(sizeof(llama_token) * (size_t) needed);
    if (tokens == NULL) {
        return -1;
    }

    int32_t got = llama_tokenize(vocab, text, len, tokens, needed, true, true);
    if (got < 0) {
        got = -got;
    }
    *out = tokens;
    return got;
}

intptr_t lain_load(const char * path, int32_t n_ctx, int32_t n_threads,
                   char * err, int32_t err_len) {
    if (path == NULL || path[0] == '\0') {
        lain_set_error(err, err_len, "ruta del modelo vacía");
        return 0;
    }
    if (n_ctx < 512) {
        n_ctx = 512;
    }
    if (n_threads < 1) {
        n_threads = 2;
    }

    const char * backend_error = lain_ensure_backends();
    if (backend_error != NULL) {
        lain_set_error(err, err_len, backend_error);
        return 0;
    }

    const int64_t t_load = lain_now_ms();
    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;

    struct llama_model * model = llama_model_load_from_file(path, mparams);
    if (model == NULL) {
        lain_set_error(err, err_len, "no se pudo cargar el GGUF");
        return 0;
    }

    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = (uint32_t) n_ctx;
    cparams.n_batch = (uint32_t) n_ctx;
    cparams.n_ubatch = 512;
    cparams.n_threads = n_threads;
    cparams.n_threads_batch = n_threads;

    struct llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == NULL) {
        llama_model_free(model);
        lain_set_error(err, err_len, "no se pudo crear el contexto");
        return 0;
    }

    lain_session * session = (lain_session *) calloc(1, sizeof(lain_session));
    if (session == NULL) {
        llama_free(ctx);
        llama_model_free(model);
        lain_set_error(err, err_len, "sin memoria para la sesión");
        return 0;
    }

    session->model = model;
    session->ctx = ctx;
    session->vocab = llama_model_get_vocab(model);
    session->n_ctx = (int32_t) llama_n_ctx(ctx);
    session->load_ms = lain_now_ms() - t_load;
    session->load_mode = (int32_t) mparams.load_mode;
    memset(&session->last, 0, sizeof(session->last));
    return (intptr_t) session;
}

void lain_free(intptr_t handle) {
    lain_session * session = (lain_session *) handle;
    if (session == NULL) {
        return;
    }
    if (session->ctx != NULL) {
        llama_free(session->ctx);
    }
    if (session->model != NULL) {
        llama_model_free(session->model);
    }
    free(session);
}

int32_t lain_context_size(intptr_t handle) {
    lain_session * session = (lain_session *) handle;
    return session == NULL ? 0 : session->n_ctx;
}

// Formatea system+user con la plantilla del GGUF. Devuelve los bytes necesarios.
int32_t lain_format_prompt(intptr_t handle, const char * system, const char * user,
                           char * out, int32_t out_len) {
    lain_session * session = (lain_session *) handle;
    if (session == NULL) {
        return -1;
    }

    struct llama_chat_message messages[2];
    size_t count = 0;
    if (system != NULL && system[0] != '\0') {
        messages[count].role = "system";
        messages[count].content = system;
        count++;
    }
    messages[count].role = "user";
    messages[count].content = user != NULL ? user : "";
    count++;

    const char * tmpl = llama_model_chat_template(session->model, NULL);
    if (tmpl != NULL) {
        return llama_chat_apply_template(tmpl, messages, count, true, out, out_len);
    }

    return snprintf(out, out_len > 0 ? (size_t) out_len : 0,
                    "<|im_start|>system\n%s<|im_end|>\n"
                    "<|im_start|>user\n%s<|im_end|>\n"
                    "<|im_start|>assistant\n",
                    system != NULL ? system : "", user != NULL ? user : "");
}

// Genera hasta max_tokens y emite cada pieza por `cb`. Devuelve los tokens emitidos.
int32_t lain_generate_ex(intptr_t handle, const char * prompt, int32_t max_tokens,
                         float temp, float top_p, int32_t top_k, float repeat_penalty,
                         int32_t seed, lain_piece_cb cb, void * user_data,
                         char * err, int32_t err_len) {
    lain_session * session = (lain_session *) handle;
    if (session == NULL) {
        lain_set_error(err, err_len, "sesión nula");
        return -1;
    }
    if (prompt == NULL || prompt[0] == '\0') {
        lain_set_error(err, err_len, "prompt vacío");
        return -1;
    }

    memset(&session->last, 0, sizeof(session->last));
    session->last.instrumented = 1;
    const int64_t t_start = lain_now_ms();

    llama_token * tokens = NULL;
    const int32_t n_tokens = lain_tokenize(session->vocab, prompt, &tokens);
    if (n_tokens <= 0 || tokens == NULL) {
        free(tokens);
        lain_set_error(err, err_len, "no se pudo tokenizar el prompt");
        return -1;
    }
    session->last.n_prompt_tokens = n_tokens;
    if (n_tokens >= session->n_ctx) {
        free(tokens);
        lain_set_error(err, err_len, "el prompt no cabe en el contexto");
        return -1;
    }

    llama_memory_clear(llama_get_memory(session->ctx), true);

    const int32_t k = top_k > 0 ? top_k : 40;
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    struct llama_sampler * sampler = llama_sampler_chain_init(sparams);
    // La penalización solo se añade si se pide algo distinto de "desactivada":
    // así la cadena es idéntica a la de producción con repeat_penalty = 1.0.
    if (repeat_penalty > 0.0f && repeat_penalty != 1.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
            llama_vocab_n_tokens(session->vocab), 64, repeat_penalty, 0.0f, 0.0f));
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(k));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temp));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist((uint32_t) seed));

    int32_t produced = 0;
    const int64_t t_prefill_start = lain_now_ms();
    struct llama_batch batch = llama_batch_get_one(tokens, n_tokens);
    if (llama_decode(session->ctx, batch) != 0) {
        lain_set_error(err, err_len, "falló el decode del prompt");
        produced = -1;
        goto cleanup;
    }
    const int64_t t_prefill_end = lain_now_ms();
    session->last.prefill_ms = t_prefill_end - t_prefill_start;

    int32_t n_past = n_tokens;
    bool first_piece = true;
    char piece[512];
    while (produced < max_tokens && n_past < session->n_ctx - 1) {
        llama_token id = llama_sampler_sample(sampler, session->ctx, -1);
        if (llama_vocab_is_eog(session->vocab, id)) {
            break;
        }
        llama_sampler_accept(sampler, id);

        const int32_t len = llama_token_to_piece(session->vocab, id, piece,
                                                 (int32_t) sizeof(piece), 0, false);
        if (first_piece) {
            session->last.ttft_ms = lain_now_ms() - t_start;
            first_piece = false;
        }
        if (len > 0 && cb != NULL) {
            cb(piece, len, user_data);
        }

        batch = llama_batch_get_one(&id, 1);
        if (llama_decode(session->ctx, batch) != 0) {
            lain_set_error(err, err_len, "falló el decode del token");
            break;
        }
        n_past++;
        produced++;
    }
    session->last.decode_ms = lain_now_ms() - t_prefill_end;
    session->last.n_generated_tokens = produced > 0 ? produced : 0;
    session->last.n_threads = llama_n_threads(session->ctx);
    session->last.n_batch_threads = llama_n_threads_batch(session->ctx);
    session->last.n_ctx = session->n_ctx;
    session->last.load_mode = session->load_mode;
    session->last.n_backend = (int32_t) ggml_backend_reg_count();
    session->last.load_ms = session->load_ms;

cleanup:
    llama_sampler_free(sampler);
    free(tokens);
    return produced;
}

// Compatibilidad con la firma de producción: top_k 40 y sin penalización.
int32_t lain_generate(intptr_t handle, const char * prompt, int32_t max_tokens,
                      float temp, float top_p, int32_t seed,
                      lain_piece_cb cb, void * user_data,
                      char * err, int32_t err_len) {
    return lain_generate_ex(handle, prompt, max_tokens, temp, top_p, 40, 1.0f, seed,
                            cb, user_data, err, err_len);
}

int32_t lain_last_metrics(intptr_t handle, lain_metrics * out) {
    lain_session * session = (lain_session *) handle;
    if (session == NULL || out == NULL) {
        return 0;
    }
    *out = session->last;
    return 1;
}
