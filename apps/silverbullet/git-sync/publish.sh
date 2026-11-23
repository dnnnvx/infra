#!/bin/sh
# git-sync exechook: runs in the synced worktree after every new commit.
# Copies docs/src into the docs space as <space>/<repo>, swapping it in whole
# so SilverBullet never sees a half-copied tree. Dot-prefixed temp dirs stay
# out of the space index.
set -eu
dest=/space/$REPO_NAME
rm -rf "/space/.$REPO_NAME.new" "/space/.$REPO_NAME.old"
cp -r docs/src "/space/.$REPO_NAME.new"
if [ -d "$dest" ]; then mv "$dest" "/space/.$REPO_NAME.old"; fi
mv "/space/.$REPO_NAME.new" "$dest"
rm -rf "/space/.$REPO_NAME.old"
