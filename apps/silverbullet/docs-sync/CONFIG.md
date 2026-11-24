Docs space configuration. Managed in git (infra: apps/silverbullet/docs-sync/CONFIG.md) and copied here by docs-sync: edit it there. The look and feel lives next to it in STYLE.md.

```space-lua
-- priority: 100
-- Every top-level folder is one synced repo; its landing page is the first of
-- docs.homes that exists, else its first page in name order.
docs = docs or {}
docs.homes = { "index", "README", "SUMMARY", "introduction", "overview" }
-- top-level folders that aren't repos (SilverBullet's own pages, repo metadata)
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

-- One entry per synced repo: its pages, landing page, and the #repo object
-- docs-sync writes to Repositories/<repo> (url, branch, commit, date, subject).
function docs.repos()
  local meta = {}
  for _, m in ipairs(query[[from m = index.tag "repo" select m]]) do
    if m.repo then meta[m.repo] = m end
  end
  local groups = query[[
    from p = index.pages()
    where p.name:find("/", 1, true)
    group by p.name:match("^[^/]+")
    select { repo = key, pages = group }
    order by repo
  ]]
  local repos = {}
  for _, g in ipairs(groups) do
    if not docs.exclude[g.repo] then
      table.insert(repos, {
        name = g.repo,
        home = docs.home(g.repo, g.pages),
        pages = g.pages,
        meta = meta[g.repo] or {},
      })
    end
  end
  return repos
end

-- A page's description: its frontmatter description, else its first paragraph.
function docs.summary(ref)
  local ok, text = pcall(space.readPage, ref)
  if not ok or not text then return nil end
  local extracted = index.extractFrontmatter(text, {
    removeFrontMatterSection = true,
    removeTags = true,
  })
  local fm = extracted.frontmatter or {}
  if fm.description then return fm.description end
  local fence = string.rep("`", 3)
  for _, line in ipairs(string.split(extracted.text, "\n")) do
    local t = string.trim(line)
    if t ~= "" and not t:startsWith("#") and not t:startsWith("$" .. "{")
      and not t:startsWith(fence) and not t:startsWith(">")
      and not t:startsWith("-") and not t:startsWith("*") then
      return t
    end
  end
end

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

function docs.card(r)
  local m = r.meta
  local footer = { class = "docs-card-footer", dom.span { plural(#r.pages, "page") } }
  if m.commit then
    table.insert(footer, dom.span { class = "docs-card-commit", m.commit:sub(1, 7) })
  end
  if m.date then table.insert(footer, dom.span { m.date }) end
  if m.url then
    table.insert(footer, dom.a {
      class = "docs-card-link", href = m.url, target = "_blank", rel = "noopener",
      "Source ↗",
    })
  end
  return dom.div {
    class = "docs-card",
    dom.div {
      class = "docs-card-body",
      onclick = function() editor.navigate(r.home) end,
      dom.div { class = "docs-card-title", r.name },
      dom.div { class = "docs-card-desc", docs.summary(r.home) or "" },
      m.subject and dom.div { class = "docs-card-subject", "Latest: " .. m.subject } or nil,
    },
    dom.div(footer),
  }
end

-- Front page: one card per synced repo.
function docs.repoCards()
  local cards = {}
  for _, r in ipairs(docs.repos()) do table.insert(cards, docs.card(r)) end
  if #cards == 0 then return "_No repositories synced yet._" end
  return widget.htmlBlock(dom.div { class = "docs-cards", table.unpack(cards) })
end

-- Repository pages (Repositories/<repo>) get an icon and render their
-- frontmatter as the same card instead of raw YAML.
tag.define {
  name = "repo",
  transform = function(o)
    if o.tag == "page" then o.pageDecoration = { icon = "git-branch" } end
    return o
  end,
  renderFrontmatter = function(pageMeta)
    for _, r in ipairs(docs.repos()) do
      if r.name == pageMeta.repo then
        return widget.htmlBlock(dom.div { class = "docs-cards", docs.card(r) })
      end
    end
  end,
}
```

# Sidebar
An mdbook-style table of contents, generated from the synced repos: one section per repo (opening it shows the repo's landing page), its pages titled by their first heading.

```space-lua
local function pretty(segment)
  local s = segment:gsub("[-_]+", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
end

view.define {
  name = "docs.navigate",
  title = "Contents",
  command = "Navigate: Documentation",
  dock = "lhs",
  supportedDocks = { "lhs", "rhs", "modal" },
  followEditor = true,
  placeholder = "Filter pages...",
  refreshOn = { "index" },
  source = function()
    local titles = {}
    for _, h in ipairs(query[[from h = index.headers() where h.level == 1 select h]]) do
      if not titles[h.page] then titles[h.page] = h.name end
    end
    local rows = { { name = "Home", ref = "index", icon = "home" } }
    for _, r in ipairs(docs.repos()) do
      table.insert(rows, { name = r.name, ref = r.home, icon = "book", hasChildren = #r.pages > 1 })
      local children = {}
      for _, p in ipairs(r.pages) do
        if p.name ~= r.home then
          local parts = string.split(p.name, "/")
          for i = 2, #parts - 1 do parts[i] = pretty(parts[i]) end
          local title = titles[p.name] or pretty(parts[#parts])
          parts[#parts] = title:gsub("/", "-")
          table.insert(children, { name = table.concat(parts, "/"), ref = p.name, icon = "file-text" })
        end
      end
      table.sort(children, function(a, b) return a.name:lower() < b.name:lower() end)
      for _, c in ipairs(children) do table.insert(rows, c) end
    end
    return rows
  end,
  presentation = {
    mode = "tree",
    foldersFirst = false,
    limit = 1000,
    row = {
      icon = function(o)
        if o.isFolder and not o.ref then return "folder" end
        return o.icon or "file-text"
      end,
    },
  },
  onSelect = function(o)
    if o.ref then editor.navigate(o.ref) end
    if o.hasChildren then return "navigator:expand" end
  end,
}

config.set("view.defaults", {
  ["docs.navigate"] = { open = true, width = 260 },
})
```
