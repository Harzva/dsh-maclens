#!/bin/bash
# Create the awesome-dsh-plugin PR for dsh-maclens.
# Run AFTER 2026-08-19 17:03 UTC (repo is then 1 day old).
#
# Usage: bash pr/01-create-pr.sh
set -euo pipefail

TOKEN="${GITHUB_TOKEN:-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}"
REPO="awesome-dsh-plugin/awesome-dsh-plugin"
HEAD="Harzva:add-dsh-maclens"
BASE="main"

# Guard: refuse to run before the 1-day gate.
python3 - <<'PY'
from datetime import datetime, timezone, timedelta
created = datetime(2026, 8, 18, 17, 3, 14, tzinfo=timezone.utc)
if datetime.now(timezone.utc) < created + timedelta(days=1):
    raise SystemExit("refusing: repo is not 1 day old yet")
PY

echo "Creating PR: $HEAD -> $BASE on $REPO"
curl -s --max-time 30 -X POST \
  -H "Authorization: token $TOKEN" \
  -H "User-Agent: dsh-maclens-setup" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/pulls" \
  -d "$(cat <<JSON
{
  "title": "Add Harzva/dsh-maclens to the vision category",
  "head": "$HEAD",
  "base": "$BASE",
  "body": "## What\n\nAdd [Harzva/dsh-maclens](https://github.com/Harzva/dsh-maclens) to the **vision** category.\n\ndsh-maclens bridges Apple's **on-device Vision framework** (macOS) into DeepSeek Harness as local tools: OCR (zh-Hans + 30 languages), image classification, face detection, document layout, and a combined describe — 100% offline, no API key, no daemon, with tall-screenshot slicing.\n\n## Checklist\n\n- [x] Repo declares \`dsh.bundle\` in package.json (installable via \`dsh plugin add dsh-maclens\`)\n- [x] npm package published: [dsh-maclens@0.1.2](https://www.npmjs.com/package/dsh-maclens)\n- [x] Repo is > 1 day old and has 11 commits\n- [x] \`dsh-plugin\` topic added\n- [x] One YAML file only: \`data/plugins/Harzva__dsh-maclens.yml\`; READMEs regenerated\n- [x] CI on the plugin repo is green (Swift build + smoke tests + plugin load + pack check)"
}
JSON
)" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if 'number' in d:
    print('PR created:', d['html_url'])
    print('number:', d['number'])
    print('state:', d['state'])
else:
    print('ERROR:', json.dumps(d, indent=1))
"