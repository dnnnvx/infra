#!/bin/sh

echo "Preparing pre-commit hooks..."

FORCE="false"
for var in "$@"; do
  if [ $var = "-f" ] || [ $var = "--force" ]; then
    FORCE="true"
  fi
done

if [ ! -f .git/hooks/pre-commit ]; then
  touch .git/hooks/pre-commit
elif [ $FORCE != "true" ]; then
  echo ".git/hooks/pre-commit already exists, skipping (use ´-f´ or ´--force´ to overwrite it)."
  exit 1
fi

echo -e '#!/bin/sh\n' > .git/hooks/pre-commit

find 'hooks' -type f -exec sh -c '
  for file in "$@"; do
    echo "# ${file}" >> .git/hooks/pre-commit
    cat $file >> .git/hooks/pre-commit
    echo "" >> .git/hooks/pre-commit
  done
' sh  {} +
chmod +x .git/hooks/pre-commit
echo "New .git/hooks/pre-commit script created"
