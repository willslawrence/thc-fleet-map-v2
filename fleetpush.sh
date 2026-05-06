#!/bin/bash
# THC Fleet Map — generate from vault and push to GitHub
set -euo pipefail
cd ~/Projects/FleetMapAndTimeline

LOG="./fleetpush.log"
trap 'echo "$(date "+%Y-%m-%d %H:%M:%S") ❌ fleetpush failed at line $LINENO" >> "$LOG"' ERR
exec > >(tee -a "$LOG") 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') — Fleet map generation started"
python3 generate.py
git add -A
git diff --cached --quiet || git commit -m "Fleet sync $(date '+%Y-%m-%d %H:%M')"
git push
echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ Done"
