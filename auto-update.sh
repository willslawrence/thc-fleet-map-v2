#!/usr/bin/env bash
# auto-update.sh — Regenerate fleet map and push to GitHub
# Scheduled to run at 08:45 and 13:00 Saudi Arabia time (GMT+3)
#
# To manually run: bash auto-update.sh
# To test without push: bash auto-update.sh --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

LOG="$SCRIPT_DIR/fleetpush.log"
trap 'echo "$(date "+%Y-%m-%d %H:%M:%S") ❌ auto-update failed at line $LINENO" >> "$LOG"' ERR
exec > >(tee -a "$LOG") 2>&1

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "🚁 THC Fleet Map Auto-Update"
echo "   $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo ""

# 0. Pull first so generation runs on the latest state (a manual push from
#    another machine won't jam the scheduled run).
echo "🔄 Pulling latest..."
git pull --rebase --autostash || { echo "⚠️  pull --rebase failed — continuing"; git rebase --abort 2>/dev/null || true; }

# 1. Run the generator
echo "📊 Generating fleet map..."
python3 generate.py

# 2. Check for changes
if git diff --quiet && git diff --cached --quiet; then
    echo "✅ No changes detected — skipping push"
    exit 0
fi

# 3. Stage and commit
echo "📦 Committing changes..."
git add -A
git commit -m "Auto-update: $(date '+%d %b %Y %H:%M')"

# 4. Push (unless dry-run)
if [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY RUN — would push to GitHub"
else
    echo "🚀 Pushing to GitHub..."
    # If the remote moved in the meantime, rebase once and retry.
    git push || { git pull --rebase --autostash && git push; }
    echo "✅ Live at: https://willslawrence.github.io/thc-ops-map/"
fi

echo ""
echo "Done!"
