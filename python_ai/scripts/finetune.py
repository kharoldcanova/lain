"""Fine-tuning de MiniCPM para personalidad en español con Unsloth."""

from pathlib import Path

from unsloth import FastLanguageModel
from trl import SFTTrainer
from transformers import TrainingArguments
from datasets import load_dataset, concatenate_datasets

MODEL_NAME = "openbmb/MiniCPM-2B-sft-bf16"
MAX_SEQ_LENGTH = 2048
LOCAL_DATASET = Path(__file__).resolve().parents[1] / "datasets" / "personality_es.jsonl"
SYSTEM_PROMPT = (Path(__file__).resolve().parents[1] / "datasets" / "system_prompt.txt").read_text().strip()
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "outputs"
HF_DATASET = "mlabonne/guanaco-llama2-1k"


def format_local(example):
    return {
        "text": f"<|system|>\n{SYSTEM_PROMPT}\n<|user|>\n{example['instruction']}\n<|assistant|>\n{example['response']}"
    }


def format_hf(example):
    # guanaco format: "### Human: ... ### Assistant: ..."
    text = example.get("text", "")
    return {"text": f"<|system|>\n{SYSTEM_PROMPT}\n{text}"}


def load_data():
    local = load_dataset("json", data_files=str(LOCAL_DATASET), split="train")
    local = local.map(format_local, remove_columns=local.column_names)

    hf = load_dataset(HF_DATASET, split="train")
    hf = hf.map(format_hf, remove_columns=hf.column_names)

    return concatenate_datasets([local, hf])


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
