#!/bin/bash
set -euo pipefail
target="${1:?Pass the source export directory}"
[[ -d "$target" && "$target" != / ]] || exit 2
# Do not echo matching lines: a failed scan must not disclose a credential.
if find "$target" -type f \( -name '*.sqlite*' -o -name '*.jsonl' -o -name '*.log' -o -name '*.pem' -o -name '*.p12' -o -name '.env' -o -name 'credentials.json' \) | /usr/bin/grep -q .; then
  echo 'FAIL: private runtime or credential file found in export.' >&2; exit 1
fi
if /usr/bin/grep -rIlE '(/Users/[[:alnum:]_.-]+/|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[[:alnum:]]{30,}|sk-[[:alnum:]]{32,})' "$target"; then
  echo 'FAIL: inspect the listed files for personal paths or secrets.' >&2; exit 1
fi
if /usr/bin/grep -riIl 'job''right' "$target"; then
  echo 'FAIL: unrelated integration reference.' >&2; exit 1
fi
echo 'Source audit passed: no detected personal paths, secret patterns, unrelated integration references, or runtime files.'
echo 'This bounded scan is not a guarantee; review the export before publication.'
