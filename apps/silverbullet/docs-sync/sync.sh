#!/bin/bash
# Every $PERIOD seconds, mirrors <docs path> of each repo in /config/repos into
# /space/<folder>. Shallow, sparse, blobless clones: only the docs are fetched.
# A repo's folder is swapped in whole, and only when its commit changed.
# Each repo also gets a #repo page, /space/Repositories/<folder>.md, with its
# url, branch and last commit (rendered as cards by CONFIG.md).
# Removing a repo from the list leaves its folder and page behind: delete them by hand.
set -uo pipefail
trap 'exit 0' TERM INT

# YAML double-quoted string
yq_str() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

write_repo_page() {
  local name=$1 url=$2 ref=$3 dir=$4 commit date subject
  commit=$(git -C "$dir" log -1 --format=%H) &&
    date=$(git -C "$dir" log -1 --format=%cs) &&
    subject=$(git -C "$dir" log -1 --format=%s) || return 1
  mkdir -p /space/Repositories || return 1
  cat >"/space/Repositories/.$name.md.new" <<EOF_PAGE || return 1
---
tags: repo
repo: $(yq_str "$name")
url: $(yq_str "${url%.git}")
branch: $(yq_str "$ref")
commit: $(yq_str "$commit")
date: $(yq_str "$date")
subject: $(yq_str "$subject")
---
Written by docs-sync on every new commit: edits here are overwritten.
EOF_PAGE
  mv "/space/Repositories/.$name.md.new" "/space/Repositories/$name.md"
}

sync_repo() {
  local name=$1 url=$2 ref=$3 path=$4
  local dir=/git/$name stamp=/git/$name.published head
  if [[ ! -d $dir/.git ]]; then
    rm -rf "$dir"
    git clone --quiet --depth 1 --filter=blob:none --sparse --branch "$ref" "$url" "$dir" &&
      git -C "$dir" sparse-checkout set "$path" || return 1
  else
    git -C "$dir" fetch --quiet --depth 1 origin "$ref" &&
      git -C "$dir" reset --quiet --hard FETCH_HEAD || return 1
  fi
  head=$(git -C "$dir" rev-parse HEAD) || return 1
  if [[ -d /space/$name && -f /space/Repositories/$name.md && -f $stamp && $(<"$stamp") == "$head" ]]; then
    return 0
  fi
  [[ -d $dir/$path ]] || { echo "$name: no $path at $head" >&2; return 1; }
  # dot-prefixed temp dirs stay out of the SilverBullet index
  rm -rf "/space/.$name.new" "/space/.$name.old"
  cp -r "$dir/$path" "/space/.$name.new" || return 1
  if [[ -d /space/$name ]]; then mv "/space/$name" "/space/.$name.old"; fi
  mv "/space/.$name.new" "/space/$name" && rm -rf "/space/.$name.old" || return 1
  write_repo_page "$name" "$url" "$ref" "$dir" || return 1
  echo "$head" >"$stamp"
  echo "$name: published $head"
}

while true; do
  # the space's front page, config and style are managed in git too (replaced only when they differ)
  for f in index.md CONFIG.md STYLE.md; do
    if [[ ! -f /space/$f || "$(</space/$f)" != "$(</config/$f)" ]]; then
      cp "/config/$f" "/space/.$f.new" && mv "/space/.$f.new" "/space/$f" &&
        echo "$f: published"
    fi
  done
  while read -r name url ref path; do
    [[ -z ${name:-} || $name == \#* ]] && continue
    sync_repo "$name" "$url" "$ref" "$path" || echo "$name: sync failed" >&2
  done </config/repos
  sleep "$PERIOD" &
  wait $!
done
