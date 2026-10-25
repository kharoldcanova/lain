"""Fine-tuning de MiniCPM para personalidad en español con Unsloth.

Uso:
    python scripts/finetune.py                         # entrenamiento completo
    python scripts/finetune.py --max-steps 1 --skip-hf # smoke test rápido
"""

import argparse
from pathlib import Path

import unsloth  # noqa: F401  (debe importarse antes de trl/transformers)
import torch
from datasets import concatenate_datasets, load_dataset
from trl import SFTConfig, SFTTrainer
from unsloth import FastLanguageModel

ROOT = Path(__file__).resolve().parents[1]
LOCAL_DATASET = ROOT / "datasets" / "personality_es.jsonl"
SYSTEM_PROMPT = (ROOT / "datasets" / "system_prompt.txt").read_text().strip()
DEFAULT_OUTPUT_DIR = ROOT / "outputs"
DEFAULT_MODEL = "openbmb/MiniCPM5-2B"
HF_DATASET = "mlabonne/guanaco-llama2-1k"


def build_formatter(tokenizer):
    def format_local(example):
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": example["instruction"]},
            {"role": "assistant", "content": example["response"]},
        ]
        return {"text": tokenizer.apply_chat_template(messages, tokenize=False)}

    return format_local


def format_hf(example):
    # guanaco format: "### Human: ... ### Assistant: ..."
    return {"text": f"<|system|>\n{SYSTEM_PROMPT}\n{example.get('text', '')}"}


def load_data(tokenizer, include_hf=True):
    local = load_dataset("json", data_files=str(LOCAL_DATASET), split="train")
    local = local.map(build_formatter(tokenizer), remove_columns=local.column_names)

    if not include_hf:
        return local

    hf = load_dataset(HF_DATASET, split="train")
    hf = hf.map(format_hf, remove_columns=hf.column_names)
    return concatenate_datasets([local, hf])


def parse_args():
    parser = argparse.ArgumentParser(description="Fine-tuning QLoRA de LAIN con Unsloth.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Modelo base de HuggingFace.")
    parser.add_argument("--max-steps", type=int, default=60, help="Pasos de entrenamiento.")
    parser.add_argument("--max-seq-length", type=int, default=2048)
    parser.add_argument("--batch-size", type=int, default=2)
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--skip-hf", action="store_true", help="No mezclar el dataset de HuggingFace.")
    parser.add_argument("--no-export", action="store_true", help="Omitir la exportación a GGUF.")
    return parser.parse_args()


def main():
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model,
        max_seq_length=args.max_seq_length,
        dtype=None,
        load_in_4bit=True,
        trust_remote_code=True,
    )

    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        target_modules=[
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ],
        lora_alpha=32,
        lora_dropout=0.05,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=42,
    )

    dataset = load_data(tokenizer, include_hf=not args.skip_hf)

    use_bf16 = torch.cuda.is_bf16_supported()
    trainer = SFTTrainer(
        model=model,
        train_dataset=dataset,
        processing_class=tokenizer,
        args=SFTConfig(
            output_dir=str(output_dir),
            dataset_text_field="text",
            max_length=args.max_seq_length,
            per_device_train_batch_size=args.batch_size,
            gradient_accumulation_steps=4,
            warmup_steps=5,
            max_steps=args.max_steps,
            learning_rate=2e-4,
            bf16=use_bf16,
            fp16=not use_bf16,
            logging_steps=1,
            report_to="none",
            seed=42,
        ),
    )

    trainer.train()

    if args.no_export:
        print(f"Entrenamiento finalizado sin exportar (salida: {output_dir})")
        return

    model.save_pretrained_gguf(str(output_dir), tokenizer, quantization_method="q4_k_m")

    # Unsloth escribe los GGUF en <output_dir>_gguf; los movemos a outputs/.
    gguf_dir = output_dir.parent / f"{output_dir.name}_gguf"
    for gguf in gguf_dir.glob("*.gguf"):
        gguf.replace(output_dir / gguf.name)

    print(f"Modelo exportado a {output_dir}")


if __name__ == "__main__":
    main()
