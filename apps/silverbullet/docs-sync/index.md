---
description: Project documentation, mirrored from each repo's docs folder.
---
Project documentation, mirrored from each repository's docs folder every few minutes. Pages are read-only here: edit them in the repository.

# Projects
${docs.repoList()}

```space-lua
-- Managed in git (infra: apps/silverbullet/docs-sync/index.md), copied here by docs-sync.
-- Every top-level folder is one synced repo; its landing page is the first of
-- docs.homes that exists, else its first page in name order.
docs = docs or {}
docs.homes = { "index", "README", "SUMMARY", "introduction", "overview" }

function docs.home(repo, pages)
  local names = {}
  for _, p in ipairs(pages) do names[p.name] = true end
  for _, h in ipairs(docs.homes) do
    if names[repo .. "/" .. h] then return repo .. "/" .. h end
  end
  local first
  for _, p in ipairs(pages) do
    if not first or p.name < first then first = p.name end
  end
  return first
end

function docs.repoList()
  local repos = query[[
    from p = index.pages()
    where p.name:find("/", 1, true) and not p.name:startsWith("Library/")
    group by p.name:match("^[^/]+")
    select { repo = key, home = docs.home(key, group), pages = #group }
    order by repo
  ]]
  if #repos == 0 then return "_No repositories synced yet._" end
  local lines = {}
  for _, r in ipairs(repos) do
    table.insert(lines, "* [[" .. r.home .. "|" .. r.repo .. "]] (" .. r.pages .. " pages)")
  end
  return widget.markdown(table.concat(lines, "\n"))
end
```
