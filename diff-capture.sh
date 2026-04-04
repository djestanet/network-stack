#!/bin/bash
set -e

REPO_ROOT="/srv/network-stack"
DIFF_DIR="$REPO_ROOT/diffs"
LABEL="${1:-generic}"

timestamp() {
  date '+%Y%m%d-%H%M%S'
}

TS=$(timestamp)
WORKDIR="/tmp/network-stack-diff-$TS"
mkdir -p "$WORKDIR" "$DIFF_DIR"

BEFORE="$WORKDIR/before"
AFTER="$WORKDIR/after"

mkdir -p "$BEFORE" "$AFTER"

echo "Capturing BEFORE snapshot..."
rsync -a --delete /etc/ "$BEFORE/etc/"
rsync -a --delete /opt/ "$BEFORE/opt/"

echo "Run your install/upgrade now, then press ENTER to continue..."
read -r

echo "Capturing AFTER snapshot..."
rsync -a --delete /etc/ "$AFTER/etc/"
rsync -a --delete /opt/ "$AFTER/opt/"

OUT="$DIFF_DIR/${LABEL}-${TS}.diff"
echo "Generating diff → $OUT"
diff -ru "$BEFORE" "$AFTER" > "$OUT" || true

echo "Diff capture complete: $OUT"