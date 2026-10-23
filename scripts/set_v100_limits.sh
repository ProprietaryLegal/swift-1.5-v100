#!/usr/bin/env bash
# Example power and clock caps for V100-SXM2-32GB cards serving the 27B TP4 profile. Under load these cards are
# power-bound, so the power limit sets throughput more than the clock ceiling. Values are what we run; size them to
# your own power supply and circuit. CLOCK_MHZ must be a supported graphics clock (nvidia-smi -q -d SUPPORTED_CLOCKS);
# -lgc 0,<cap> keeps idle downclocking. Needs root. Re-apply at boot (e.g. a oneshot systemd unit).
set -euo pipefail
POWER_W=${POWER_W:-180}
CLOCK_MHZ=${CLOCK_MHZ:-1425}
nvidia-smi -pm 1
nvidia-smi -pl "$POWER_W"
nvidia-smi -lgc 0,"$CLOCK_MHZ"
nvidia-smi --query-gpu=index,power.limit,clocks.max.sm --format=csv
