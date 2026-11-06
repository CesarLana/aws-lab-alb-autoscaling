#!/bin/bash
# ==============================================================================
# AWS Lab: ALB + Auto Scaling Group
# Script: scripts/stress_test.sh
# Purpose: Generate synthetic CPU load to trigger CloudWatch alarm and ASG scale-out.
# ==============================================================================

DURATION_MINUTES=${1:-10}
CORES=$(nproc)

echo "=========================================================="
echo " AWS Auto Scaling CPU Stress Test"
echo " Duration: ${DURATION_MINUTES} minutes"
echo " Detected Cores: ${CORES}"
echo " Target ASG Policy: > 50% CPU utilization"
echo "=========================================================="

if command -v stress &>/dev/null; then
  echo "[+] Running 'stress' tool on ${CORES} CPU workers..."
  stress --cpu "${CORES}" --timeout "${DURATION_MINUTES}m" --verbose
elif command -v stress-ng &>/dev/null; then
  echo "[+] Running 'stress-ng' tool on ${CORES} CPU workers..."
  stress-ng --cpu "${CORES}" --timeout "${DURATION_MINUTES}m" --metrics-brief
else
  echo "[!] stress/stress-ng not found. Installing via dnf/yum..."
  if command -v dnf &>/dev/null; then
    sudo dnf install -y stress || sudo dnf install -y stress-ng || true
  fi

  if command -v stress &>/dev/null; then
    stress --cpu "${CORES}" --timeout "${DURATION_MINUTES}m"
  else
    echo "[*] Falling back to POSIX dd/yes loop to peg CPU to 100%..."
    PIDS=()
    for ((i=1; i<=CORES; i++)); do
      sha256sum /dev/zero &
      PIDS+=($!)
    done

    echo "[+] Stress processes started with PIDs: ${PIDS[*]}"
    echo "[+] Sleeping for ${DURATION_MINUTES} minutes..."
    sleep "$((DURATION_MINUTES * 60))"

    echo "[+] Killing stress loops..."
    for pid in "${PIDS[@]}"; do
      kill -9 "$pid" 2>/dev/null || true
    done
  fi
fi

echo "=========================================================="
echo "[✓] Stress test completed. Monitor CloudWatch metric:"
echo "    AWS/EC2 -> CPUUtilization or AWS/ApplicationELB"
echo "=========================================================="
