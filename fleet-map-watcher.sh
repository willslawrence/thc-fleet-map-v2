#!/bin/bash
# Fleet Map Auto-Regenerator
# Watches Obsidian vault folders for changes, then runs generate.py + git push
# Debounces: waits 2 minutes after last change before regenerating

VAULT_BASE="$HOME/Library/CloudStorage/OneDrive-TheHelicopterCompany/THC Vault/THC"
FLEET_REPO="$HOME/Projects/thc-fleet-map-v2"
DEBOUNCE_SEC=300
LOG="/tmp/openclaw/fleet-map-watcher.log"

mkdir -p "$(dirname "$LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

regenerate() {
    log "🔄 Regenerating fleet map..."
    cd "$FLEET_REPO" || { log "❌ Cannot cd to $FLEET_REPO"; return 1; }
    
    if python3 generate.py >> "$LOG" 2>&1; then
        log "✅ generate.py succeeded"
        git add -A >> "$LOG" 2>&1
        if git diff --cached --quiet; then
            log "ℹ️ No changes to commit"
        else
            git commit -m "Auto-update fleet map (vault change detected)" >> "$LOG" 2>&1
            git push >> "$LOG" 2>&1
            log "✅ Pushed to GitHub"
        fi
    else
        log "❌ generate.py failed (exit $?)"
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
    
    # Wait for iCloud sync to settle
    log "⏳ Waiting ${DEBOUNCE_SEC}s for sync to settle..."
    sleep "$DEBOUNCE_SEC"
    
    LAST_TRIGGER=$(date +%s)
    regenerate
done
