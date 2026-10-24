"""Prueba de inferencia del modelo fine-tuneado exportado a GGUF."""

from pathlib import Path

from llama_cpp import Llama

MODEL_PATH = Path(__file__).resolve().parents[1] / "outputs" / "minicpm-lain-q4_k_m.gguf"
SYSTEM_PROMPT = (Path(__file__).resolve().parents[1] / "datasets" / "system_prompt.txt").read_text().strip()


def main():
    llm = Llama(model_path=str(MODEL_PATH), n_ctx=2048, n_gpu_layers=-1, verbose=False)

    prompt = f"<|system|>\n{SYSTEM_PROMPT}\n<|user|>\nHola, ¿cómo estás?\n<|assistant|>\n"
    output = llm(prompt, max_tokens=128, stop=["<|user|>"], echo=False)
    print(output["choices"][0]["text"].strip())


if __name__ == "__main__":
    main()
