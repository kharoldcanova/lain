// Puente C mínimo entre Dart (dart:ffi) y llama.cpp para Android.
// Expone solo lo que la app necesita: cargar el GGUF, formatear el turno con la
// plantilla del modelo y generar texto emitiendo cada pieza por callback.
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "llama.h"

typedef void (*lain_piece_cb)(const char * piece, int32_t len, void * user_data);

typedef struct {
    struct llama_model * model;
    struct llama_context * ctx;
    const struct llama_vocab * vocab;
    int32_t n_ctx;
} lain_session;

static void lain_set_error(char * err, int32_t err_len, const char * msg) {
    if (err == NULL || err_len <= 0) {
        return;
    }
    snprintf(err, (size_t) err_len, "%s", msg);
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

    llama_backend_init();

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
int32_t lain_generate(intptr_t handle, const char * prompt, int32_t max_tokens,
                      float temp, float top_p, int32_t seed,
                      lain_piece_cb cb, void * user_data,
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

    llama_token * tokens = NULL;
    const int32_t n_tokens = lain_tokenize(session->vocab, prompt, &tokens);
    if (n_tokens <= 0 || tokens == NULL) {
        free(tokens);
        lain_set_error(err, err_len, "no se pudo tokenizar el prompt");
        return -1;
    }
    if (n_tokens >= session->n_ctx) {
        free(tokens);
        lain_set_error(err, err_len, "el prompt no cabe en el contexto");
        return -1;
    }

    llama_memory_clear(llama_get_memory(session->ctx), true);

    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    struct llama_sampler * sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temp));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist((uint32_t) seed));

    int32_t produced = 0;
    struct llama_batch batch = llama_batch_get_one(tokens, n_tokens);
    if (llama_decode(session->ctx, batch) != 0) {
        lain_set_error(err, err_len, "falló el decode del prompt");
        produced = -1;
        goto cleanup;
    }

    int32_t n_past = n_tokens;
    char piece[512];
    while (produced < max_tokens && n_past < session->n_ctx - 1) {
        llama_token id = llama_sampler_sample(sampler, session->ctx, -1);
        if (llama_vocab_is_eog(session->vocab, id)) {
            break;
        }
        llama_sampler_accept(sampler, id);

        const int32_t len = llama_token_to_piece(session->vocab, id, piece,
                                                 (int32_t) sizeof(piece), 0, false);
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

cleanup:
    llama_sampler_free(sampler);
    free(tokens);
    return produced;
}
