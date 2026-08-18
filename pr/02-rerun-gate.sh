#!/bin/bash
# Re-trigger the awesome-dsh-plugin Submission gate for PR #1784 after the
# repo reaches 1 day old, so the age check turns green.
#
# Run AFTER 2026-08-19 17:03 UTC (repo is then 1 day old).
# Re-triggering = push an empty commit to the PR head branch, which re-runs
# the PR check workflow and, via workflow_run, the Submission gate.
#
# Usage: bash pr/02-rerun-gate.sh
set -euo pipefail

TOKEN="${GITHUB_TOKEN:-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}"
FORK="Harzva/awesome-dsh-plugin"
BRANCH="add-dsh-maclens"
PR_URL="https://github.com/awesome-dsh-plugin/awesome-dsh-plugin/pull/1784"

# Guard: refuse before the 1-day gate.
python3 - <<'PY'
from datetime import datetime, timezone, timedelta
created = datetime(2026, 8, 18, 17, 3, 14, tzinfo=timezone.utc)
if datetime.now(timezone.utc) < created + timedelta(days=1):
    raise SystemExit("refusing: repo is not 1 day old yet")
print("repo is 1 day old — re-triggering the gate")
PY

echo "Pushing an empty commit to $FORK:$BRANCH to re-trigger checks..."
WORK=$(mktemp -d)
git clone --depth 1 "https://github.com/$FORK.git" "$WORK/repo" >/dev/null 2>&1
cd "$WORK/repo"
git config user.name "Harzva"
git config user.email "harzva@gmail.com"
git checkout -b "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1
git commit --allow-empty -m "ci: re-trigger submission gate (repo now 1 day old)" >/dev/null
git -c credential.helper="!f() { echo 'username=x-access-token'; echo 'password=$TOKEN'; }; f" \
  push origin "$BRANCH" 2>&1 | tail -2
rm -rf "$WORK"

echo "Gate re-triggered. Watch: $PR_URL"
echo "Next: confirm the Submission gate check turns green, then wait for a maintainer merge."
