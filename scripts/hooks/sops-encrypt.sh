REQ_COMMANDS=( "yq" "sops" "age" )
for COMMAND in "${REQ_COMMANDS[@]}"; do
  if ! type $COMMAND > /dev/null; then
    echo "Missing $COMMAND command."
    exit 1
  fi
done

FILES=$(git diff --cached --name-only)
for FILE in $FILES; do
  if [ -f "$FILE" ]; then
    sops --encrypt --in-place $FILE 2>/dev/null
    # adjust identation until https://github.com/getsops/sops/pull/1273 is part of the next release
    yq e -Pi $FILE
    git add $FILE
    echo "Encrypted secret in $FILE"
  fi
done
