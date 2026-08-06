#!/bin/bash
# THC Fleet Map — generate from vault and push to GitHub
set -euo pipefail
# Resolve the repo from this script's own location — the old hardcoded
# ~/Projects/thc-fleet-map-v2 has not existed since the move under
# ~/Connected/Cowork/Projects/, so every run died on the cd (2026-08-06).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

LOG="$SCRIPT_DIR/fleetpush.log"
trap 'echo "$(date "+%Y-%m-%d %H:%M:%S") ❌ fleetpush failed at line $LINENO" >> "$LOG"' ERR
exec > >(tee -a "$LOG") 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') — Fleet map generation started"

# Pull first so generation runs on the latest state (a manual push from
# another machine won't jam the scheduled run).
git pull --rebase --autostash || { echo "⚠️  pull --rebase failed — continuing"; git rebase --abort 2>/dev/null || true; }

python3 generate.py

# Skip the publish when the ONLY change is the "Last updated" stamp.
#
# generate.py rewrites that stamp on every run, so an hourly job committed and
# pushed even when no fleet data had moved — ~21 pushes/day, each firing a full
# Pages deploy. That volume is what causes the "job was not acquired by Runner
# of type hosted" failures this repo kept hitting (2026-08-06).
if ! git diff --quiet -- index.html; then
    substantive=$(git diff -U0 -- index.html \
        | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
        | grep -vE 'LAST_UPDATED' || true)
    if [ -z "$substantive" ]; then
        echo "⏭️  Only the 'Last updated' stamp changed — nothing to publish"
        git checkout -- index.html
    fi
fi

git add -A
git diff --cached --quiet || git commit -m "Fleet sync $(date '+%Y-%m-%d %H:%M')"

# Push; if the remote moved in the meantime, rebase once and retry.
git push || { git pull --rebase --autostash && git push; }
echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ Done"
