/// Arquitecturas que el motor nativo incluido en este APK sabe cargar.
///
/// La lista se verificó contra el propio binario compilado (llama.cpp
/// `caa8191`) y no contra documentación:
///
/// ```
/// strings -a android/app/src/main/jniLibs/arm64-v8a/libllama.so
/// ```
///
/// Se comparó cada nombre de `LLM_ARCH_NAMES` del fuente con los literales
/// presentes en `libllama.so`; solo se conservaron los que aparecen. Cuando se
/// recompile el motor (`tools/build_llama_android.sh`) hay que repetir esa
/// verificación y actualizar esta lista junto con `LLAMA_COMMIT`.
///
/// `gguf_header.dart` lee `general.architecture` del archivo y este conjunto
/// decide si el modelo se puede activar. Un modelo se puede descargar aunque
/// no sea compatible: la descarga nunca se bloquea, la activación sí.
library;

/// Arquitecturas soportadas por el motor incluido en el APK.
///
/// Nótese que `lfm2` y `lfm2moe` están presentes (LFM2.5 funciona hoy) y
/// `lfm3` **no** (LFM3-1.7B requiere recompilar llama.cpp).
const Set<String> supportedEngineArchitectures = <String>{
  'clip',
  'llama',
  'llama4',
  'deci',
  'falcon',
  'grok',
  'gpt2',
  'gptj',
  'gptneox',
  'baichuan',
  'starcoder',
  'refact',
  'bert',
  'modern-bert',
  'nomic-bert',
  'nomic-bert-moe',
  'neo-bert',
  'jina-bert-v2',
  'jina-bert-v3',
  'eurobert',
  'bloom',
  'stablelm',
  'qwen',
  'qwen2',
  'qwen2moe',
  'qwen2vl',
  'sensenova_u1',
  'qwen3',
  'flint',
  'qwen3moe',
  'qwen3next',
  'qwen3vl',
  'qwen3vlmoe',
  'qwen35',
  'qwen35moe',
  'clef',
  'vllm-decision2',
  'qwen4exp',
  'phi2',
  'phi3',
  'phimoe',
  'plamo',
  'plamo2',
  'plamo3',
  'codeshell',
  'orion',
  'internlm2',
  'minicpm',
  'minicpm3',
  'gemma',
  'gemma2',
  'gemma3',
  'gemma3n',
  'gemma4',
  'gemma4-assistant',
  'gemma-embedding',
  'gemma-embedding2',
  'starcoder2',
  'mamba',
  'mamba2',
  'maple',
  'jamba',
  'falcon-h1',
  'xverse',
  'command-r',
  'cohere2',
  'cohere2moe',
  'dbrx',
  'olmo',
  'olmo2',
  'olmoe',
  'muse-glimmer',
  'muse-spark',
  'openelm',
  'arctic',
  'deepseek',
  'deepseek2',
  'deepseek2-ocr',
  'deepseek32',
  'deepseek4',
  'deepseek41',
  'chatglm',
  'glm4',
  'glm4moe',
  'glm-dsa',
  'bitnet',
  't5encoder',
  'jais',
  'jais2',
  'nemotron',
  'nemotron_h',
  'nemotron_h_moe',
  'exaone',
  'exaone4',
  'exaone-moe',
  'rwkv6',
  'rwkv6qwen2',
  'rwkv7',
  'arwkv7',
  'granite',
  'granitemoe',
  'granitehybrid',
  'graniteswitch',
  'granite_swa',
  'chameleon',
  'wavtokenizer-dec',
  'bailingmoe',
  'bailingmoe2',
  'bailingmoe3',
  'dots1',
  'dots3note',
  'arcee',
  'afmoe',
  'laguna',
  'ernie4_5',
  'ernie4_5-moe',
  'hunyuan-moe',
  'hunyuan-dense',
  'hunyuan_vl',
  'hy_v3',
  'hy_v4',
  'smollm3',
  'gpt-oss',
  'lfm2',
  'lfm2moe',
  'dream',
  'smallthinker',
  'llada',
  'llada-moe',
  'seed_oss',
  'grovemoe',
  'apertus',
  'minimax-01',
  'hrm_text',
  'minimax-m2',
  'minimax-m3',
  'cogvlm',
  'rnd1',
  'pangu-embedded',
  'mistral3',
  'eagle3',
  'dflash',
  'mistral4',
  'paddleocr',
  'mimo2',
  'step35',
  'spark2_5',
  'llama-embed',
  'maincoder',
  'maion-coder',
  'kimi-linear',
  'kimi-k3',
  'glm5-next',
  'talkie',
  'mellum',
  'nanbeige',
  'qwen3tts',
  'pockettts',
  'k2-horizon',
  'beam',
  'kolibri1',
};

/// Arquitecturas conocidas que este motor todavía no soporta.
///
/// Se usan para dar un mensaje claro en la UI en lugar de un error genérico
/// de carga. No es una lista de todo lo que existe: cualquier arquitectura
/// fuera de [supportedEngineArchitectures] se trata como no soportada.
const Set<String> knownUnsupportedArchitectures = <String>{
  'lfm3',
};

/// `true` si el motor incluido puede cargar un modelo de [architecture].
///
/// Una arquitectura desconocida (`null`, vacía o `desconocida`) devuelve
/// `true`: son instalaciones anteriores a la sonda y se dejan intentar, el
/// error de carga real se muestra al usuario.
bool isArchitectureSupported(String? architecture) {
  final arch = architecture?.trim().toLowerCase();
  if (arch == null || arch.isEmpty || arch == 'desconocida') return true;
  return supportedEngineArchitectures.contains(arch);
}
