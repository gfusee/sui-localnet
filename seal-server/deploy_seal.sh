publish_json() {
  local dir="$1"
  log "+ (cd $dir && sui client publish --json)"
  ( cd "$dir" && sui client publish --json ) | awk '
    BEGIN { found=0 }
    {
      if (!found) {
        pos = index($0, "{")
        if (pos) {
          found=1
          print substr($0, pos)
        }
        next
      }
      print
    }
  '
}

SEAL_JSON="$(publish_json "/seal/move/seal")"

PACKAGE_ID="$(
  jq -r '[.objectChanges[] | select(.type=="published")] | last | .packageId' \
    <<< "$SEAL_JSON"
)"

echo "$PACKAGE_ID"
