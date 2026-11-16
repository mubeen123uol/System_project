#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/rebuild.sh
# Purpose: Fully automated end-to-end teardown and rebuild entirely from code
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=================================================================="
echo " [REBUILD] INITIATING FULL PLATFORM REBUILD FROM CODE"
echo " Goal: Verify infrastructure-as-code idempotency and resilience"
echo "=================================================================="
START_TIME=$(date +%s)

# Step 1: Teardown everything
"${PROJECT_ROOT}/scripts/teardown.sh"

echo ""
echo "Sleeping 3 seconds before automated reconstruction..."
sleep 3
echo ""

# Step 2: Deploy everything from code
"${PROJECT_ROOT}/scripts/deploy.sh"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "=================================================================="
echo " ==> PLATFORM REBUILT ENTIRELY FROM CODE IN ${DURATION} SECONDS! <== "
echo "=================================================================="
