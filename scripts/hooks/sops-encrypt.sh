if ! type sops > /dev/null; then
  echo "Missing `sops` command."
  exit 1
fi
FILES=$(git diff --cached --name-only)
for FILE in $FILES; do
  if [ -f "$FILE" ]; then
    sops --encrypt --in-place $FILE 2>/dev/null
    git add $FILE
  fi
done
