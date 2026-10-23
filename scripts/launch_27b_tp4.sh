#!/usr/bin/env bash
# Serve a Qwen3.8-27B-family NVFP4 checkpoint (Swift 1.5 or Qwen3.8-27B QUASAR) with the DFlash2 drafter on
# four peer-connected V100-SXM2-32GB GPUs (TP4 inside one NVLink board), using the 1Cat-vLLM 1.5.1 wheel.
#
# The arguments are the 1Cat-vLLM 1.5.1 release 27B command (RELEASE_NOTES, "Installation and launch") with these
# departures, all measured on our hardware:
#   - 3 concurrent sequences instead of 4 (power headroom; see README "Power");
#   - compact grammar-constrained JSON (xgrammar, no whitespace) for structured outputs;
#   - thinking off by default in the chat template (turn it on per request);
#   - a local copy of the pinned DFlash2 draft revision dedf8df6.
# Async scheduling and FULL_AND_PIECEWISE CUDA graphs come from the wheel's default policy; compile caching is on by
# default. Swift 1.5's ModelOpt mixed-precision export (NVFP4 MLP, FP8 attention) loads through 1Cat's exact-SM70
# TurboMind W4A16 / W8A16 paths, on by default; no conversion step is needed.
set -euo pipefail
VENV=${ONECAT_VENV:-$PWD/.venv}
MODEL=${MODEL:?set MODEL to the local model directory (e.g. /models/Swift-1.5-Qwen3.8-27b-NVFP4)}
DRAFT=${DRAFT:?set DRAFT to the local DFlash2 directory (e.g. /models/Qwen3.8-27B-DFlash2)}
SERVED_NAME=${SERVED_NAME:-swift-1.5-27b}
HOST=${HOST:-127.0.0.1}
PORT=${PORT:-8000}
GPUS=${GPUS:?set GPUS to four GPU UUIDs on one NVLink board, comma separated}
[[ "$GPUS" =~ ^(GPU-[0-9a-f-]+,){3}GPU-[0-9a-f-]+$ ]] || { echo "need four GPU UUIDs on one board: $GPUS" >&2; exit 1; }
export CUDA_VISIBLE_DEVICES="$GPUS" PYTHONNOUSERSITE=1 HF_HUB_OFFLINE=1
# A standard CUDA 12.8 toolkit (nvcc), a C++ compiler and ninja must be on PATH for the remaining TileLang JIT.
export CUDA_HOME=${CUDA_HOME:-/usr/local/cuda-12.8}
export PATH="$VENV/bin:$CUDA_HOME/bin:$PATH"
exec vllm serve "$MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  --dtype half \
  --tensor-parallel-size 4 \
  --attention-backend FLASH_ATTN_V100 \
  --kv-cache-dtype fp8_e4m3 \
  --max-model-len 262144 \
  --gpu-memory-utilization 0.8 \
  --max-num-batched-tokens 8192 \
  --max-num-seqs 3 \
  --block-size 2048 \
  --mamba-block-size 8192 \
  --enable-prefix-caching \
  --mamba-cache-mode align \
  --served-model-name "$SERVED_NAME" \
  --limit-mm-per-prompt '{"image":0,"video":0}' \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 \
  --structured-outputs-config '{"backend":"xgrammar","disable_any_whitespace":true}' \
  --default-chat-template-kwargs '{"enable_thinking":false}' \
  --seed 0 \
  --speculative-config "{\"method\":\"dflash\",\"model\":\"$DRAFT\",\"num_speculative_tokens\":7,\"kv_cache_dtype\":\"auto\",\"attention_backend\":\"FLASH_ATTN_V100\",\"draft_sample_method\":\"probabilistic\",\"enforce_eager\":false}" \
  --trust-remote-code \
  "$@"
