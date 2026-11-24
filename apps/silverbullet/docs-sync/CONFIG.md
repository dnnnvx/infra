Docs space configuration. Managed in git (infra: apps/silverbullet/docs-sync/CONFIG.md) and copied here by docs-sync: edit it there.

```space-lua
-- Every top-level folder is one synced repo; its landing page is the first of
-- docs.homes that exists, else its first page in name order.
docs = docs or {}
docs.homes = { "index", "README", "SUMMARY", "introduction", "overview" }
-- top-level folders that aren't repos (SilverBullet's own pages)
docs.exclude = { Library = true, Repositories = true }

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
    where p.name:find("/", 1, true)
    group by p.name:match("^[^/]+")
    select { repo = key, home = docs.home(key, group), pages = #group }
    order by repo
  ]]
  local lines = {}
  for _, r in ipairs(repos) do
    if not docs.exclude[r.repo] then
      local n = r.pages == 1 and "1 page" or (r.pages .. " pages")
      table.insert(lines, "* [[" .. r.home .. "|" .. r.repo .. "]] (" .. n .. ")")
    end
  end
  if #lines == 0 then return "_No repositories synced yet._" end
  return widget.markdown(table.concat(lines, "\n"))
end
```
