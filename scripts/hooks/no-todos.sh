if git grep --cached -q 'TODO' -- ':!scripts/hooks/no-todos.sh'; then
    echo 'Your commit contains TODO comments. Resolve them before committing.'
    exit 1
fi
