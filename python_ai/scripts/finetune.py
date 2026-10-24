"""Fine-tuning de MiniCPM para personalidad en español con Unsloth."""

import json
from pathlib import Path

from unsloth import FastLanguageModel
from trl import SFTTrainer
from transformers import TrainingArguments
from datasets import load_dataset

MODEL_NAME = "openbmb/MiniCPM-2B-sft-bf16"
MAX_SEQ_LENGTH = 2048
DATASET_PATH = Path(__file__).resolve().parents[1] / "datasets" / "personality_es.jsonl"
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "outputs"


def load_data():
    return load_dataset("json", data_files=str(DATASET_PATH), split="train")


def main():
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=MODEL_NAME,
        max_seq_length=MAX_SEQ_LENGTH,
        dtype=None,
        load_in_4bit=True,
    )

    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
        lora_alpha=16,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing="unsloth",
    )

    dataset = load_data()

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=MAX_SEQ_LENGTH,
        args=TrainingArguments(
            per_device_train_batch_size=2,
            gradient_accumulation_steps=4,
            warmup_steps=5,
            max_steps=60,
            learning_rate=2e-4,
            fp16=True,
            logging_steps=1,
            output_dir=str(OUTPUT_DIR),
        ),
    )

    trainer.train()
    model.save_pretrained_gguf(str(OUTPUT_DIR), tokenizer, quantization_method="q4_k_m")
    print(f"Modelo exportado a {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
