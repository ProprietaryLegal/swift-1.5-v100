# Swift 1.5 (Qwen3.8-27B family) on 4× V100: 1Cat-vLLM 1.5.1 serving recipe and A/B against Qwen

<!-- pli:blurb:start -->

> Published by [PLI Labs](https://proprietarylegal.ai/labs.html), the open research arm of [Proprietary Legal Intelligence](https://proprietarylegal.ai). PLI builds AI systems around a legal organization's own work product, combining retrieval, staged workflows, validation, and attorney review. Visit [proprietarylegal.ai](https://proprietarylegal.ai) to explore our work and discuss what your organization needs.

<!-- pli:blurb:end -->


**Serving recipe and measurements, not model weights.** PLI Labs runs Swift 1.5, a Qwen3.8-27B fine-tune by UkisAI, as its
default local legal-drafting model on owned V100-SXM2-32GB hardware. This repository publishes the exact launch profile, the
power settings it runs under, and a measured comparison with the regular Qwen3.8-27B NVFP4 build on the same stack.

Hugging Face entry: https://huggingface.co/ProprietaryLegal/swift-1.5-27b-v100-serving

## What we got

- **Same quality, about half the reasoning.** On six family-law drafting tasks graded blind against the attorney's filed
  document, Swift tied Qwen on four and beat it on two, with none worse. It used 52% fewer completion tokens and 50% less
  reasoning time.
- **About half the wall time.** Critical-path time fell 34–59% (mean 49%) on the four tasks run on identical hardware.
- **No loss of raw speed at short context.** Decode is 247.7 vs 247.9 tok/s at a ~12K-token prompt on four V100s.
- **Runs on the stock 1Cat-vLLM 1.5.1 wheel.** Swift's official ModelOpt mixed-precision export (NVFP4 MLP, FP8
  attention) loads through 1Cat's SM70 TurboMind paths with no conversion.

Full numbers and caveats: [COMPARISON.md](COMPARISON.md).

## Hardware

- 4× NVIDIA V100-SXM2-32GB on one SXM2 board with a full NVLink mesh. Run tensor parallel 4 inside one board only; do not
  span boards with vLLM (board-to-board traffic is PCIe).
- Linux x86_64, CPython 3.12, GLIBC ≥ 2.38, NVIDIA driver 570.124.06 or newer (tested 580.173.02).
- A standard CUDA 12.8 toolkit (nvcc), a C++ compiler and ninja on PATH: the wheel still JIT-compiles some TileLang
  kernels.

## Install

1. Get the 1Cat-vLLM 1.5.1 wheel and its `SHA256SUMS` from the
   [1Cat-vLLM v1.5.1 release](https://github.com/1CatAI/1Cat-vLLM/releases/tag/v1.5.1) (source `release/1.5.1`, commit
   `589a5d1e1a9ea7c42d533eed724a7d67c5f1779d`; wheel SHA256
   `757f2200ba6bd20f7e3e5c8fc68c7e05461df6d284baf676ac0c16ce19434959`).

   ```bash
   sha256sum -c SHA256SUMS
   uv venv --python 3.12 .venv
   uv pip install --python .venv/bin/python ./1cat_vllm-1.5.1-cp312-cp312-linux_x86_64.whl
   ```

2. Download the weights (read the Swift licence first; see "Licences" below):

   ```bash
   hf download ukisai/Swift-1.5-Qwen3.8-27b-NVFP4 \
     --revision 25482027debd5485e8108897ba9fed8d3ba16595 --local-dir /models/Swift-1.5-Qwen3.8-27b-NVFP4
   hf download incoai/Qwen3.8-27B-DFlash2 \
     --revision dedf8df68adfb1afeaf7b7480c0a0243108177b4 --local-dir /models/Qwen3.8-27B-DFlash2
   # Baseline for the comparison (optional):
   hf download QUASAR-QAT/Qwen3.8-27B-QUASAR-NVFP4 \
     --revision 15d2e47bffe5d8ad23928879f8f7d2f74909e259 --local-dir /models/Qwen3.8-27B-QUASAR-NVFP4
   ```

## Launch

```bash
sudo scripts/set_v100_limits.sh            # optional; see "Power"
MODEL=/models/Swift-1.5-Qwen3.8-27b-NVFP4 \
DRAFT=/models/Qwen3.8-27B-DFlash2 \
GPUS=GPU-AAAA,GPU-BBBB,GPU-CCCC,GPU-DDDD \
PORT=8000 scripts/launch_27b_tp4.sh
```

Pin the four GPUs by UUID (`nvidia-smi -L`), all on the same board. For the Qwen baseline, set
`MODEL=/models/Qwen3.8-27B-QUASAR-NVFP4 SERVED_NAME=qwen3.8-27b`; every other argument is identical. Extra arguments after
the script name go to `vllm serve` and override the script's own.

Startup: the first start compiles and takes about 3.5 minutes; with the warm compile cache a restart takes about 2 minutes.
Check `GET /v1/sm70/acceleration` once it is up: the 27B NVFP4 + DFlash2 profile should report all acceleration paths
enabled.

## Profile and tuning notes

The arguments are the 1Cat-vLLM 1.5.1 release 27B command, with four measured departures:

| Setting | Value | Why |
|---|---|---|
| Tensor parallel | 4, Flash-V100 attention | release profile |
| Target KV cache | `fp8_e4m3` | the long-context grouped-attention route engages only with E4M3 |
| Draft | DFlash2, 7 probabilistic tokens, FP16 draft KV | release profile |
| Context / prefill | 262,144 / 8,192 batched tokens | release profile |
| Concurrent sequences | **3** (release: 4) | power headroom on our circuit |
| Structured outputs | **xgrammar, no whitespace** | compact JSON for tool and schema-constrained calls |
| Thinking | **off by default** in the chat template | turn it on per request where reasoning helps |
| Memory fraction / blocks | 0.80; KV 2048, Mamba 8192; prefix caching; Mamba align | release profile |

Async scheduling, FULL_AND_PIECEWISE CUDA graphs and compile caching come from the wheel's default policy; no performance
environment variables are needed.

## Power

Under sustained load these cards are power-bound: the clock settles wherever the power limit allows. We run every card at
**180 W with a 1425 MHz graphics-clock ceiling** (`scripts/set_v100_limits.sh`), applied at boot. Two fully loaded 4-card
boards drew about 1.4 kW of GPU power at peak in our measurements, so size the limits to your supply and
circuit, and bring boards up one at a time after any power loss.

## Licences

This repository (scripts and documentation) is Apache-2.0 ([LICENSE](LICENSE)); attributions are in [NOTICE](NOTICE). It
contains no model weights. The components it runs carry their own terms:

| Component | Licence | Notes |
|---|---|---|
| 1Cat-vLLM 1.5.1 | Apache-2.0 | https://github.com/1CatAI/1Cat-vLLM |
| Qwen3.8-27B (base model) | Apache-2.0 | Alibaba Cloud |
| Qwen3.8-27B QUASAR NVFP4 | Apache-2.0 | baseline only |
| DFlash2 drafter | Apache-2.0 | incoai/Qwen3.8-27B-DFlash2 (mirror z-lab/Qwen3.8-27B-DFlash2) |
| **Swift 1.5** | **Swift Open License v1.0** (UkisAI) | **commercial use is licensed only below a revenue threshold; see below** |

Swift Open License v1.0, §5 (quoted): "(a) The rights granted under this License for Commercial Use are conditioned upon
You or Your Legal Entity not exceeding the Threshold. (b) Any Commercial Use of the Work or a Derivative Work by a Legal
Entity that exceeds the Threshold is not licensed under this License." The Threshold is "gross revenue of one million
United States dollars (US$1,000,000) or more, measured over the most recently completed fiscal year of You together with
every Legal Entity that controls, is controlled by, or is under common control with You." Entities above it can obtain a
separate "Swift Enterprise License" from UkisAI. Read the full licence in the model repository before use.

"Swift" and "UkisAI" are UkisAI's names, used here only to identify the model this recipe serves. PLI Labs is not
affiliated with UkisAI, Alibaba Cloud, 1CatAI or the DFlash authors.

## Limits

- Six tasks, one run each, is a small sample; the comparison's caveats (a power-cap difference between arms, quantization
  method) are listed in [COMPARISON.md](COMPARISON.md).
- Legal outputs from any local model are drafts for attorney review.
- Measured October 2026 on owned hardware with 1Cat-vLLM 1.5.1; results on other drivers, toolkits or clocks will differ.

## Links

- https://proprietarylegal.com
- https://proprietarylegal.ai
- [PLI Labs hub repo](https://github.com/ProprietaryLegal/pli-labs) (V100 research index: research/v100)

<!-- pli:footer:start -->

---

## About PLI Labs

“Your proprietary work product is your proprietary intelligence.” PLI Labs is the open research arm of Proprietary Legal Intelligence. We publish legal model prunes, serving recipes for owned hardware, and open-source tools so readers can inspect our methods and test our claims before hiring us.

Founded by a practicing trial lawyer, PLI builds AI systems around a legal organization's own work product: retrieval, staged workflows, validation, and attorney review. The approach grew from systems running on live matters in a litigation practice. Our consulting work supports deployment through approved frontier APIs, private cloud, or open-weight models on hardware you own. Explore the research or contact us about your organization's work.

[Website](https://proprietarylegal.ai) · [PLI Labs](https://proprietarylegal.ai/labs.html) · [Research](https://proprietarylegal.ai/research/index.html) · [GitHub](https://github.com/ProprietaryLegal) · [Hugging Face](https://huggingface.co/ProprietaryLegal) · [Contact](https://proprietarylegal.ai/contact.html)

Proprietary Legal Intelligence LLC is a technology consultancy, not a law firm, and does not provide legal services or legal advice.

<!-- pli:footer:end -->
