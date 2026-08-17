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

# Same topic as the capture pipelines + Claude Bridge, so it lands on the phone
# with no new subscription. Override with NTFY_TOPIC= to silence (used when testing).
NTFY_TOPIC="${NTFY_TOPIC-thc-bridge-will-c333ed3bee86b1cc}"

# ping <title> <message> — phone notification via ntfy. Never fatal.
ping() {
    [ -n "$NTFY_TOPIC" ] || return 0
    curl -s -m 10 \
        -H "Title: $1" \
        -H "Priority: high" \
        -H "Tags: helicopter" \
        -d "$2" \
        "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1 || true
}

# abort <message> — stop before publishing, tell Will, leave the last-good page live.
# The map going STALE is the accepted failure mode here; the map going BROKEN is not.
# Will's call, 2026-08-17 — see [[Gotchas]] "auto-update commits git conflict markers".
abort() {
    echo "🛑 $1"
    echo "   Not committing. The last good page stays live at https://willslawrence.github.io/thc-fleet-map-v2/"
    ping "🚁 Fleet map NOT updated" "$1 — the live page is now stale until this is fixed. Run: cd ~/Connected/Cowork/Projects/thc-fleet-map-v2 && git status"
    exit 1
}

echo "🚁 THC Fleet Map Auto-Update"
echo "   $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo ""

# 0. Pull first so generation runs on the latest state (a manual push from
#    another machine won't jam the scheduled run).
echo "🔄 Pulling latest..."
# A failed pull used to warn and carry on. That is what shipped a broken page on
# 2026-08-16: the autostash conflicted, the markers stayed in index.html, and the
# script regenerated + committed + pushed them. Now it's fatal.
if ! git pull --rebase --autostash; then
    git rebase --abort 2>/dev/null || true
    abort "git pull --rebase --autostash failed — working tree may be mid-conflict"
fi

# 1. Run the generator
echo "📊 Generating fleet map..."
python3 generate.py

# 1b. Skip the publish when the ONLY change is the "Last updated" stamp.
#     generate.py rewrites it every run, so a scheduled job pushed even when no
#     fleet data had moved. See fleetpush.sh for the full note (2026-08-06).
if ! git diff --quiet -- index.html; then
    substantive=$(git diff -U0 -- index.html \
        | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
        | grep -vE 'LAST_UPDATED' || true)
    if [ -z "$substantive" ]; then
        echo "⏭️  Only the 'Last updated' stamp changed — nothing to publish"
        git checkout -- index.html
    fi
fi

# 2. Check for changes
if git diff --quiet && git diff --cached --quiet; then
    echo "✅ No changes detected — skipping push"
    exit 0
fi

# 2b. GUARD — never publish a page carrying git conflict markers.
#     generate.py rewrites index.html only BETWEEN its comment markers, so a conflict
#     elsewhere in the file survives regeneration untouched and looks fine to every
#     other check ("the notes are there", "no leaks") while the page is broken.
if grep -qE '^(<<<<<<< |>>>>>>> |=======$)' index.html; then
    echo ""
    grep -nE '^(<<<<<<< |>>>>>>> |=======$)' index.html | head
    abort "index.html contains git conflict markers"
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
    echo "✅ Live at: https://willslawrence.github.io/thc-fleet-map-v2/"
fi

echo ""
echo "Done!"
