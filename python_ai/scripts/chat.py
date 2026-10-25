"""Chat interactivo con el modelo GGUF exportado (prueba manual).

Comandos dentro del chat:
    /limpiar   reinicia la conversación
    /salir     termina el chat

Registra cada intercambio en el formato `lain_experiences.jsonl` del vault:
context (Laya), metacognition, response y training_metadata.
"""

import argparse
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

import torch  # noqa: F401  (carga libcudart antes que llama_cpp)
from llama_cpp import Llama

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = ROOT / "outputs"
DEFAULT_LOG = ROOT / "experiences" / "lain_experiences.jsonl"
SYSTEM_PROMPT = (ROOT / "datasets" / "system_prompt.txt").read_text().strip()
MAX_HISTORY_MESSAGES = 12
THOUGHT_RE = re.compile(r"<(?:think(?:ing)?|thought)>(.*?)</(?:think(?:ing)?|thought)>", re.S)


def parse_args():
    parser = argparse.ArgumentParser(description="Chat manual con el modelo LAIN.")
    parser.add_argument("--model", help="Ruta al .gguf (por defecto el primero en outputs/).")
    parser.add_argument("--n-ctx", type=int, default=4096)
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--temperature", type=float, default=0.7)
    parser.add_argument("--hide-thought", action="store_true", help="Oculta el bloque <think>.")
    parser.add_argument("--prompt", help="Mensaje único (no interactivo); útil para probar.")
    parser.add_argument("--log", default=str(DEFAULT_LOG), help="Ruta del .jsonl de experiencias.")
    parser.add_argument("--no-log", action="store_true", help="No registrar experiencias.")
    parser.add_argument("--rag", action="store_true", help="Inyectar contexto del RAG local.")
    parser.add_argument("--top-k", type=int, default=4, help="Fragmentos RAG a recuperar.")
    return parser.parse_args()


def resolve_model(path):
    if path:
        model_path = Path(path).expanduser()
        if not model_path.is_file():
            raise SystemExit(f"No existe el modelo: {model_path}")
        return model_path

    model_path = next(DEFAULT_OUTPUT_DIR.glob("*.gguf"), None)
    if model_path is None:
        raise SystemExit(f"No se encontró ningún .gguf en {DEFAULT_OUTPUT_DIR}")
    return model_path


def trim(messages):
    system, rest = messages[0], messages[1:]
    return [system] + rest[-MAX_HISTORY_MESSAGES:]


def parse_thought(text):
    """Devuelve (respuesta_externa, dict de metacognición según el esquema del vault)."""
    data = {
        "thought_trace": None,
        "prior_belief": None,
        "belief_shift": None,
        "axiom_alignment_check": None,
    }
    match = THOUGHT_RE.search(text)
    if match is None:
        return text.strip(), data

    answer = THOUGHT_RE.sub("", text).strip()
    body = match.group(1).strip()
    if body.startswith("```"):
        body = re.sub(r"^```(?:json)?\s*|\s*```$", "", body).strip()

    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        parsed = None

    if isinstance(parsed, dict):
        for key in data:
            value = parsed.get(key)
            if isinstance(value, str) and value.strip():
                data[key] = value.strip()
    else:
        data["thought_trace"] = body or None

    return answer, data


def rag_context(query, top_k):
    from rag import search

    hits = search(query, top_k)
    if not hits:
        return None
    return "\n\n".join(f"[{i}] {hit['text']}" for i, hit in enumerate(hits, 1))


def with_context(messages, context):
    trimmed = trim(messages)
    if not context:
        return trimmed
    note = {"role": "system", "content": f"Contexto recuperado (úsalo si es relevante):\n{context}"}
    return [trimmed[0], note] + trimmed[1:]


def ask(llm, messages, args, context=None):
    """Devuelve (respuesta_externa, dict de metacognición)."""
    stream = llm.create_chat_completion(
        messages=with_context(messages, context),
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        stream=True,
    )

    raw = []
    pending = ""
    deciding = True
    for chunk in stream:
        delta = chunk["choices"][0]["delta"].get("content") or ""
        raw.append(delta)
        if not args.hide_thought:
            print(delta, end="", flush=True)
            continue
        if deciding:
            pending += delta
            if "<think" not in pending and "<thought" not in pending:
                if "<think>".startswith(pending.lstrip()) or "<thought>".startswith(pending.lstrip()):
                    continue
                print(pending, end="", flush=True)
                pending, deciding = "", False
            elif "</think>" in pending or "</thought>" in pending:
                rest = re.split(r"</think>|</thought>", pending, maxsplit=1)[1]
                print(rest.lstrip("\n"), end="", flush=True)
                pending, deciding = "", False
            continue
        print(delta, end="", flush=True)

    if args.hide_thought and deciding:
        answer, _ = parse_thought(pending)
        print(answer, end="", flush=True)

    print()
    return parse_thought("".join(raw))


def log_experience(path, user_input, answer, thought):
    """Escribe una línea con el esquema `lain_experiences.jsonl` del vault."""
    record = {
        "id": f"exp_{datetime.now(timezone.utc):%Y%m%d}_{uuid.uuid4().hex[:6]}",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "trigger_type": "chat_message",
        "context": {
            "user_input": user_input,
            "laya_decision": None,
            "has_multimodal_input": False,
        },
        "metacognition": {
            "thought_trace": thought["thought_trace"],
            "prior_belief": thought["prior_belief"],
            "belief_shift": thought["belief_shift"],
            "axiom_alignment_check": thought["axiom_alignment_check"],
        },
        "response": {
            "model_output": answer,
            "user_reaction_score": None,
        },
        "training_metadata": {
            "suitable_for_sft": thought["thought_trace"] is not None,
            "suitable_for_dpo": False,
            "rejected_alternative": None,
        },
    }

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def main():
    args = parse_args()
    model_path = resolve_model(args.model)
    print(f"Modelo: {model_path}\n")

    llm = Llama(model_path=str(model_path), n_ctx=args.n_ctx, n_gpu_layers=-1, verbose=False)
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    def answer_turn(user_input):
        messages.append({"role": "user", "content": user_input})
        context = rag_context(user_input, args.top_k) if args.rag else None
        print("LAIN> ", end="", flush=True)
        answer, thought = ask(llm, messages, args, context=context)
        messages.append({"role": "assistant", "content": answer})
        if not args.no_log:
            log_experience(args.log, user_input, answer, thought)
        print()

    if args.prompt:
        answer_turn(args.prompt)
        return

    print("Chat con LAIN. Escribe /limpiar para reiniciar o /salir para terminar.\n")
    while True:
        try:
            user_input = input("tú> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not user_input:
            continue
        if user_input == "/salir":
            break
        if user_input == "/limpiar":
            messages = [{"role": "system", "content": SYSTEM_PROMPT}]
            print("(conversación reiniciada)\n")
            continue

        answer_turn(user_input)


if __name__ == "__main__":
    main()
