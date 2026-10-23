# Swift 1.5 vs Qwen3.8-27B on 4× V100: measured comparison

Both models are Qwen3.8-27B-family NVFP4 checkpoints served with the identical 1Cat-vLLM 1.5.1 TP4 profile in
[`scripts/launch_27b_tp4.sh`](scripts/launch_27b_tp4.sh), with the same DFlash2 drafter, on the same class of hardware
(four V100-SXM2-32GB in one NVLink board).

- **Swift 1.5:** `ukisai/Swift-1.5-Qwen3.8-27b-NVFP4`, revision `25482027debd5485e8108897ba9fed8d3ba16595` (UkisAI's
  official ModelOpt mixed-precision export: NVFP4 MLP, FP8 attention; post-training quantization).
- **Qwen baseline:** `QUASAR-QAT/Qwen3.8-27B-QUASAR-NVFP4`, revision `15d2e47bffe5d8ad23928879f8f7d2f74909e259`
  (quantization-aware-trained NVFP4 of `Qwen/Qwen3.8-27B`).
- **Drafter:** `incoai/Qwen3.8-27B-DFlash2`, revision `dedf8df68adfb1afeaf7b7480c0a0243108177b4`, 7 probabilistic drafts.

## 1. Raw serving speed (synthetic prompts, one request at a time, both at 180 W / 1477 MHz)

| | Swift 1.5 | Qwen3.8-27B QUASAR |
|---|---:|---:|
| Decode, ~12K-token prompt | 247.7 tok/s | 247.9 tok/s |
| Decode, ~96K-token prompt | 203.5 tok/s | 216.6 tok/s |
| Time to first token, ~96K-token prompt | 41.6 s | 35.1 s |
| DFlash2 mean acceptance length (synthetic, short / long prompt) | 5.36 / 5.31 | 4.58 / 4.92 |

Per-token decode is the same at short context. At long context Swift's first token is about 18% slower and its decode
about 6% slower, consistent with its FP8 W8A16 attention path costing a little more than the QUASAR NVFP4 path.

## 2. DFlash2 acceptance on a real legal-drafting workload

vLLM speculative-decoding metrics, every 10-second interval, weighted:

| Server | Mean acceptance length | Draft acceptance |
|---|---:|---:|
| Swift 1.5 | 3.84 | 40.5% |
| Qwen3.8-27B QUASAR (three windows) | 3.69–3.79 | 38.4–39.8% |

The synthetic advantage in §1 does not carry over to real work: on legal drafting the two are about equal.

## 3. Blind A/B on family-law drafting tasks

Six family-law drafting tasks (an answer and counterclaim, a motion, an affidavit, discovery responses, a temporary
order and a consent order) ran through the same drafting pipeline (draft, three reviews, revise) with the same sampler and
prompts. Each output was graded blind against the document the attorney actually filed and given a verdict (minor
edits, major rework, or failed).

| Measure | Swift 1.5 | Qwen3.8-27B QUASAR |
|---|---:|---:|
| Verdicts vs Qwen | **4 tied, 2 better, 0 worse** | — |
| Factual faults per task | within one of Qwen on every task; 1 vs 6 on one task | — |
| Completion tokens, six tasks | **583k (−52%)** | 1,203k |
| Reasoning time, six tasks | **7,106 s (−50%)** | 14,254 s |
| Wall time, critical path, four same-hardware tasks | **−34% to −59% (mean −49%)** | baseline |

The two "better" results: one task built a complete document where both Qwen runs failed a structural check, and one
went from major rework to minor edits.

Where the speed comes from: almost entirely shorter reasoning. Decode speed is equal (§1); Swift simply thinks about half
as much before answering, and its reviews finish sooner for the same reason.

Style costs we saw with Swift: more "confirm this" highlight notes and more fill-in placeholders in discovery drafts, and
terse internal reasoning (invisible in the output).

## Caveats (read before relying on these numbers)

- **Small sample:** six tasks, one run each. The result is "no loss of quality at half the reasoning", not a claim about
  any single task.
- **Power-cap confound:** the Qwen arm of the A/B ran at 160 W / 1200 MHz, the Swift arm at 180 W / 1425 MHz. These cards
  are power-bound under load, so the real gap is closer to the +12.5% power ratio. With a generous 20% allowance for it,
  Swift is still at least 21% faster on every comparable task.
- **Two of the six Qwen runs** were on a different 2-card host, so only their token counts compare (−51% and −60%).
- **Quantization differs:** Swift's 4-bit is post-training quantization; the Qwen baseline is quantization-aware
  trained. This compares the two checkpoints you can actually download, which is the comparison that matters in practice.
- Measured on owned hardware in October 2026 with 1Cat-vLLM 1.5.1; other drivers, toolkits or clocks will differ.
