#!/bin/bash
# THC Fleet Map — generate from vault and push to GitHub
cd ~/Projects/FleetMapAndTimeline
echo "$(date '+%Y-%m-%d %H:%M:%S') — Fleet map generation started"
python3 generate.py
git add -A
git diff --cached --quiet || git commit -m "Fleet sync $(date '+%Y-%m-%d %H:%M')"
git push
echo "$(date '+%Y-%m-%d %H:%M:%S') — Done"
