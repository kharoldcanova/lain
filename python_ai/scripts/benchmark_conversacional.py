# Benchmark conversacional en español para candidatos al modelo móvil de LAIN.
#
# 60 escenarios, mismos para todos los candidatos, con las mismas condiciones:
# system prompt de LAIN (datasets/system_prompt.txt), sampling no-thinking
# (temperature 0.7, top_p 0.8, top_k 20), n_ctx 4096, max_tokens 256.
#
# Los resultados de calidad lingüística y de rendimiento se guardan separados:
#   results/<model-id>/turns.jsonl   -> transcripciones y métricas por turno
#   results/<model-id>/summary.json  -> métricas agregadas (ttft, tok/s, RAM, temperatura)
#
# Uso:
#   python scripts/benchmark_conversacional.py --server http://127.0.0.1:8080 \
#       --model-id qwen3-1.7b --out /tmp/opencode/lain-eval/results \
#       --scenarios datasets/benchmark_es.jsonl \
#       --system-prompt datasets/system_prompt.txt
"""Benchmark conversacional en español para candidatos al modelo móvil de LAIN."""

import argparse
import json
import resource
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_MAX_TOKENS = 256
DEFAULT_N_CTX = 4096


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, help="URL base del llama-server.")
    parser.add_argument("--model-id", required=True, help="Identificador del modelo evaluado.")
    parser.add_argument("--out", required=True, help="Directorio de resultados.")
    parser.add_argument("--scenarios", required=True, help="Archivo JSONL con escenarios.")
    parser.add_argument("--system-prompt", required=True, help="Archivo con el system prompt.")
    parser.add_argument("--server-pid", type=int, help="PID del llama-server para medir su RAM.")
    parser.add_argument("--temperature", type=float, default=0.7)
    parser.add_argument("--top-p", type=float, default=0.8)
    parser.add_argument("--top-k", type=int, default=20)
    parser.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS)
    parser.add_argument("--n-ctx", type=int, default=DEFAULT_N_CTX)
    parser.add_argument("--no-think", action="store_true",
                        help="Pide no-thinking vía chat_template_kwargs (Qwen3).")
    return parser.parse_args()


def load_jsonl(path):
    scenarios = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            scenarios.append(json.loads(line))
    return scenarios


def http_post_json(url, payload, timeout=600):
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code}: {body[:500]}") from error


def completion_stream(server, messages, sampling, max_tokens, no_think, timeout=600):
    """Genera la respuesta del turno y devuelve (texto, ttft_ms, completion_tokens, total_ms).

    Prueba variantes del payload por compatibilidad: primero con
    `stream_options`/`chat_template_kwargs`, luego sin cada extra.
    """
    base = {
        "messages": messages,
        "temperature": sampling["temperature"],
        "top_p": sampling["top_p"],
        "top_k": sampling["top_k"],
        "max_tokens": max_tokens,
        "stream": True,
    }
    variants = []
    first = dict(base)
    first["stream_options"] = {"include_usage": True}
    if no_think:
        first["chat_template_kwargs"] = {"enable_thinking": False}
    variants.append(first)
    if no_think:
        variants.append(dict(base, stream_options={"include_usage": True}))
    variants.append(dict(base))

    last_error = None
    for payload in variants:
        request = urllib.request.Request(
            f"{server}/v1/chat/completions", data=json.dumps(payload).encode("utf-8"),
            method="POST", headers={"Content-Type": "application/json"},
        )
        started = time.monotonic()
        first_token_at = None
        completion_tokens = 0
        parts = []
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                for raw in response:
                    line = raw.decode("utf-8").strip()
                    if not line.startswith("data:"):
                        continue
                    chunk = line[len("data:"):].strip()
                    if chunk == "[DONE]":
                        break
                    try:
                        data = json.loads(chunk)
                    except json.JSONDecodeError:
                        continue
                    choices = data.get("choices") or []
                    if choices:
                        delta = choices[0].get("delta") or {}
                        content = delta.get("content") or ""
                        if content:
                            if first_token_at is None:
                                first_token_at = time.monotonic()
                            parts.append(content)
                    usage = data.get("usage") or {}
                    completion_tokens = int(usage.get("completion_tokens") or completion_tokens)
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            last_error = f"HTTP {error.code}: {body[:300]}"
            if error.code in (400, 422, 500):
                continue  # prueba la siguiente variante del payload
            raise RuntimeError(last_error) from error

        text = "".join(parts)
        if completion_tokens == 0 and text:
            completion_tokens = max(1, len(text) // 4)  # estimación si no hubo usage
        total_ms = (time.monotonic() - started) * 1000
        ttft_ms = None if first_token_at is None else (first_token_at - started) * 1000
        return text, ttft_ms, completion_tokens, total_ms

    raise RuntimeError(f"no se pudo generar (último error: {last_error})")


def server_props(server):
    try:
        with urllib.request.urlopen(f"{server}/props", timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception:  # noqa: BLE001 — best effort
        return {}


def thermal_readings():
    """Temperaturas de las zonas térmicas (best effort, Linux)."""
    readings = {}
    zones = sorted(Path("/sys/class/thermal").glob("thermal_zone*/temp"))
    for zone in zones:
        try:
            value = int(zone.read_text().strip())
            readings[zone.name] = value / 1000.0  # mili°C -> °C
        except (OSError, ValueError):
            continue
    return readings


def process_rss_kb(pid):
    try:
        status = Path(f"/proc/{pid}/status").read_text()
        for line in status.splitlines():
            if line.startswith("VmHWM:"):
                return int(line.split()[1])
    except OSError:
        return None
    return None


def run_scenario(server, system, scenario, sampling, max_tokens, no_think):
    messages = [{"role": "system", "content": system}]
    turns = []
    for index, user_text in enumerate(scenario["turns"]):
        messages.append({"role": "user", "content": user_text})
        try:
            answer, ttft_ms, completion_tokens, total_ms = completion_stream(
                server, messages, sampling, max_tokens, no_think)
        except RuntimeError as error:
            turn = {
                "scenario_id": scenario["id"],
                "category": scenario["category"],
                "turn": index,
                "user": user_text,
                "assistant": None,
                "error": str(error),
                "ttft_ms": None,
                "completion_tokens": None,
                "total_ms": None,
            }
            turns.append(turn)
            break
        messages.append({"role": "assistant", "content": answer})
        turn = {
            "scenario_id": scenario["id"],
            "category": scenario["category"],
            "turn": index,
            "user": user_text,
            "assistant": answer,
            "error": None,
            "ttft_ms": ttft_ms,
            "completion_tokens": completion_tokens,
            "total_ms": total_ms,
        }
        turns.append(turn)
    return turns


def main():
    args = parse_args()
    scenarios = load_jsonl(args.scenarios)
    system = Path(args.system_prompt).read_text(encoding="utf-8").strip()
    out_dir = Path(args.out) / args.model_id
    out_dir.mkdir(parents=True, exist_ok=True)

    props = server_props(args.server)
    sampling = {"temperature": args.temperature, "top_p": args.top_p, "top_k": args.top_k}

    rss_before = process_rss_kb(args.server_pid) if args.server_pid else None
    temp_before = thermal_readings()
    started = time.monotonic()

    turns_path = out_dir / "turns.jsonl"
    all_turns = []
    with turns_path.open("w", encoding="utf-8") as handle:
        for scenario in scenarios:
            turns = run_scenario(
                args.server, system, scenario, sampling, args.max_tokens, args.no_think)
            for turn in turns:
                handle.write(json.dumps(turn, ensure_ascii=False) + "\n")
            all_turns.extend(turns)
            done = len([t for t in all_turns if t["error"] is None])
            print(f"[{args.model_id}] {done}/{len(all_turns)} turnos", flush=True)

    elapsed_ms = (time.monotonic() - started) * 1000
    rss_after = process_rss_kb(args.server_pid) if args.server_pid else None
    temp_after = thermal_readings()

    ok_turns = [t for t in all_turns if t["error"] is None and t["ttft_ms"] is not None]
    ttfts = [t["ttft_ms"] for t in ok_turns]
    tokens = [t["completion_tokens"] for t in ok_turns]
    gen_ms = [t["total_ms"] for t in ok_turns]

    summary = {
        "model_id": args.model_id,
        "llama_server": props.get("build_commit"),
        "build": props.get("build_number"),
        "scenarios": len(scenarios),
        "turns_total": len(all_turns),
        "turns_ok": len(ok_turns),
        "turns_error": len(all_turns) - len(ok_turns),
        "errors": sorted({t["error"] for t in all_turns if t["error"]}),
        "sampling": sampling,
        "max_tokens": args.max_tokens,
        "n_ctx": args.n_ctx,
        "elapsed_ms": round(elapsed_ms),
        "ttft_ms_avg": round(sum(ttfts) / len(ttfts), 1) if ttfts else None,
        "ttft_ms_p50": sorted(ttfts)[len(ttfts) // 2] if ttfts else None,
        "completion_tokens_total": sum(tokens),
        "tokens_per_sec_avg": round(
            sum(tokens) * 1000 / sum(gen_ms), 2) if gen_ms and sum(gen_ms) > 0 else None,
        "server_rss_kb_before": rss_before,
        "server_rss_kb_after": rss_after,
        "server_vmhwm_kb": rss_after,
        "thermal_before_c": temp_before,
        "thermal_after_c": temp_after,
        "harness_maxrss_kb": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print(f"FATAL: {error}", file=sys.stderr)
        sys.exit(1)
