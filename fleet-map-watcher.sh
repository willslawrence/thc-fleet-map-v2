#!/bin/bash
# Fleet Map Auto-Regenerator
# Watches Obsidian vault folders for changes, then runs generate.py + git push
# Debounces: waits 5 minutes after last change before regenerating

VAULT_BASE="$HOME/Library/CloudStorage/OneDrive-TheHelicopterCompany/THC Vault/THC"
FLEET_REPO="$HOME/Projects/thc-fleet-map-v2"
DEBOUNCE_SEC=300
LOG="/tmp/openclaw/fleet-map-watcher.log"
NTFY="https://ntfy.sh/thc-bridge-will-c333ed3bee86b1cc"   # same topic the ops-plan heartbeat uses

mkdir -p "$(dirname "$LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Loud failures. A silently-failing publisher is the whole reason this file
# was rewritten — see sync_to_origin() below.
alert() {
    log "$1"
    /usr/bin/curl -s -m 10 -H "Title: THC fleet-map ⚠️" -H "Priority: high" \
        -d "$1" "$NTFY" >/dev/null 2>&1
}

# Bring this clone in line with origin BEFORE regenerating.
#
# index.html is GENERATED output, so we never merge or rebase it — a history of
# auto-commits conflicts on essentially every one, and "resolving" it means hand-
# merging a file we can rebuild in one command. Origin is truth; we rebuild from
# the vault.
#
# Without this, a single push from anywhere else (a MacBook session, an agent
# worktree) leaves this clone permanently diverged: every push is rejected while
# the watcher keeps committing locally. That ran undetected 2026-07-31 → 2026-08-03,
# reaching 39 ahead / 8 behind. The live map looked fine throughout because a
# second writer was publishing — which is exactly why nobody noticed.
sync_to_origin() {
    if ! git fetch --quiet origin 2>>"$LOG"; then
        log "⚠️ git fetch failed — skipping this cycle, will retry on next change"
        return 1
    fi

    local ahead nongen
    ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ]; then
        # Never discard anything that isn't generated output.
        nongen=$(git diff --name-only origin/main...HEAD 2>/dev/null | grep -v '^index\.html$')
        if [ -n "$nongen" ]; then
            alert "fleet-map: $ahead local commit(s) on Po-Pro touch non-generated files — NOT resetting, resolve by hand: $(printf '%s' "$nongen" | tr '\n' ' ')"
            return 1
        fi
        log "♻️ Discarding $ahead local-only commit(s) (generated index.html only) — resetting to origin/main"
    fi

    # -B also recovers a detached HEAD (e.g. an abandoned rebase)
    if ! git checkout -qB main origin/main 2>>"$LOG"; then
        alert "fleet-map: could not reset to origin/main on Po-Pro"
        return 1
    fi
    return 0
}

regenerate() {
    log "🔄 Regenerating fleet map..."
    cd "$FLEET_REPO" || { log "❌ Cannot cd to $FLEET_REPO"; return 1; }

    sync_to_origin || return 1

    python3 generate.py >> "$LOG" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log "❌ generate.py failed (exit $rc)"
        return 1
    fi
    log "✅ generate.py succeeded"

    # Only the generated artifact — `git add -A` is how a .claude/worktrees
    # snapshot got committed once already (4c50975).
    git add index.html >> "$LOG" 2>&1
    if git diff --cached --quiet; then
        log "ℹ️ No changes to commit"
        return 0
    fi

    git commit -m "Auto-update fleet map (vault change detected)" >> "$LOG" 2>&1
    if git push >> "$LOG" 2>&1; then
        log "✅ Pushed to GitHub"
    else
        alert "fleet-map: git push FAILED on Po-Pro — the live map is STALE until this is resolved"
        return 1
    fi
}

log "👀 Watching:"
log "   📁 $VAULT_BASE/Helicopters/"
log "   📁 $VAULT_BASE/Missions/"
log "   📁 $VAULT_BASE/Pilots/"
log "⏱️ Debounce: ${DEBOUNCE_SEC}s (5 min)"

LAST_TRIGGER=0

fswatch -m kqueue_monitor -r \
    --include '\.md$' \
    "$VAULT_BASE/Helicopters" \
    "$VAULT_BASE/Missions" \
    "$VAULT_BASE/Pilots" | while read -r changed_file; do

    NOW=$(date +%s)
    log "📝 Change detected: $(basename "$changed_file")"

    # Debounce: skip if we regenerated less than DEBOUNCE_SEC ago
    ELAPSED=$((NOW - LAST_TRIGGER))
    if [ "$ELAPSED" -lt "$DEBOUNCE_SEC" ]; then
        log "⏳ Debouncing (${ELAPSED}s since last regen, waiting ${DEBOUNCE_SEC}s)"
        continue
    fi

    # Wait for OneDrive sync to settle
    log "⏳ Waiting ${DEBOUNCE_SEC}s for sync to settle..."
    sleep "$DEBOUNCE_SEC"

    LAST_TRIGGER=$(date +%s)
    regenerate
done
