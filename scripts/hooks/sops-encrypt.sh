REQ_COMMANDS=( "yq" "sops" "age" )
for COMMAND in "${REQ_COMMANDS[@]}"; do
  if ! type $COMMAND > /dev/null; then
    echo "Missing $COMMAND command."
    exit 1
  fi
done

FILES=$(git diff --cached --name-only)
for FILE in $FILES; do
  if [[ -f "$FILE" ]] && [[ $FILE == *.yaml ]]; then
    sops --encrypt --in-place $FILE 2>/dev/null
    yq e -Pi $FILE # adjust identation until https://github.com/getsops/sops/pull/1273 is part of the next release
    git add $FILE
  fi
done
