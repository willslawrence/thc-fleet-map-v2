#!/bin/bash
# THC Fleet Map — generate from vault and push to GitHub
set -euo pipefail
cd ~/Projects/FleetMapAndTimeline

LOG="./fleetpush.log"
trap 'echo "$(date "+%Y-%m-%d %H:%M:%S") ❌ fleetpush failed at line $LINENO" >> "$LOG"' ERR
exec > >(tee -a "$LOG") 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') — Fleet map generation started"

# Pull first so generation runs on the latest state (a manual push from
# another machine won't jam the scheduled run).
git pull --rebase --autostash || { echo "⚠️  pull --rebase failed — continuing"; git rebase --abort 2>/dev/null || true; }

python3 generate.py
git add -A
git diff --cached --quiet || git commit -m "Fleet sync $(date '+%Y-%m-%d %H:%M')"

# Push; if the remote moved in the meantime, rebase once and retry.
git push || { git pull --rebase --autostash && git push; }
echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ Done"
