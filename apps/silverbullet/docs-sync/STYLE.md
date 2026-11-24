Docs space look and feel: a clean documentation-site style (system sans-serif, neutral greys, one blue accent). Managed in git (infra: apps/silverbullet/docs-sync/STYLE.md) and copied here by docs-sync: edit it there.

```space-style
/* priority: 50 */
html {
  --ui-font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --editor-font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --docs-mono: ui-monospace, "SF Mono", "JetBrains Mono", Menlo, Consolas, monospace;
  --editor-width: 780px;

  --ui-accent-color: #0070f3;
  --root-background-color: #ffffff;
  --root-color: #171717;
  --top-background-color: rgba(255, 255, 255, 0.85);
  --top-border-color: #eaeaea;
  --ui-surface-border-color: #eaeaea;
  --panel-background-color: #fafafa;
  --panel-border-color: #eaeaea;
  --subtle-color: #666666;
  --subtle-background-color: #f5f5f5;

  --editor-heading-color: #000000;
  --editor-link-color: #0070f3;
  --editor-wiki-link-page-color: #0070f3;
  --editor-wiki-link-page-background-color: transparent;
  --link-color: #0070f3;
  --editor-code-background-color: #f5f5f5;
  --editor-blockquote-background-color: transparent;
  --editor-blockquote-border-color: #0070f3;
  --editor-blockquote-color: #444444;
  --editor-table-head-background-color: #fafafa;
  --editor-table-head-color: #171717;
  --editor-table-even-background-color: transparent;
  --editor-widget-background-color: #eaeaea;
  --editor-frontmatter-background-color: transparent;

  --docs-card-background: #ffffff;
  --docs-card-hover-border: #999999;
}

html[data-theme="dark"] {
  --ui-accent-color: #3291ff;
  --root-background-color: #0a0a0a;
  --root-color: #ededed;
  --top-background-color: rgba(10, 10, 10, 0.85);
  --top-border-color: #262626;
  --ui-surface-border-color: #262626;
  --panel-background-color: #0f0f0f;
  --panel-border-color: #262626;
  --subtle-color: #a1a1a1;
  --subtle-background-color: #171717;

  --editor-heading-color: #ffffff;
  --editor-link-color: #3291ff;
  --editor-wiki-link-page-color: #3291ff;
  --link-color: #3291ff;
  --editor-code-background-color: #171717;
  --editor-blockquote-border-color: #3291ff;
  --editor-blockquote-color: #a1a1a1;
  --editor-table-head-background-color: #171717;
  --editor-table-head-color: #ededed;
  --editor-widget-background-color: #262626;

  --docs-card-background: #111111;
  --docs-card-hover-border: #555555;
}

/* Top bar: thin, translucent, hairline below (Vercel/Next.js docs) */
#sb-top {
  border-bottom: 1px solid var(--top-border-color);
  backdrop-filter: saturate(180%) blur(8px);
}

/* Body text: comfortable reading size and line height (mdbook) */
#sb-main .cm-editor {
  font-size: 16px;
  line-height: 1.75;
}

#sb-main .cm-editor .sb-line-h1,
#sb-main .cm-editor .sb-line-h2,
#sb-main .cm-editor .sb-line-h3,
#sb-main .cm-editor .sb-line-h4 {
  font-weight: 600;
  letter-spacing: -0.02em;
  line-height: 1.3;
}
#sb-main .cm-editor .sb-line-h1 { font-size: 2.1em; padding-top: 0.6em; padding-bottom: 0.2em; }
#sb-main .cm-editor .sb-line-h2 {
  font-size: 1.5em;
  padding-top: 1.2em;
  padding-bottom: 0.3em;
  border-bottom: 1px solid var(--ui-surface-border-color);
}
#sb-main .cm-editor .sb-line-h3 { font-size: 1.2em; padding-top: 0.9em; }
#sb-main .cm-editor .sb-line-h4 { font-size: 1.05em; padding-top: 0.6em; }

/* Code: monospace, rounded blocks */
#sb-main .cm-editor .sb-code,
#sb-main .cm-editor .sb-line-fenced-code,
.sb-markdown-widget code,
.sb-markdown-widget pre {
  font-family: var(--docs-mono);
  font-size: 0.875em;
}
#sb-main .cm-editor .sb-line-code .sb-code {
  border-radius: 4px;
  padding: 0.15em 0.35em;
}
#sb-main .cm-editor .sb-line-fenced-code {
  padding-left: 1em !important;
  padding-right: 1em !important;
}
#sb-main .cm-editor .sb-line-code-outside {
  border-radius: 6px;
}

/* Links: accent colour, underline on hover only */
#sb-main .cm-editor .sb-wiki-link,
#sb-main .cm-editor .sb-link {
  text-decoration: none;
}
#sb-main .cm-editor .sb-wiki-link:hover,
#sb-main .cm-editor .sb-link:hover {
  text-decoration: underline;
}

/* Tables: light header, row hairlines, no dark header bar */
#sb-main .cm-editor .sb-table-widget table {
  border-collapse: collapse;
}
#sb-main .cm-editor .sb-table-widget th,
#sb-main .cm-editor .sb-table-widget td {
  border-bottom: 1px solid var(--ui-surface-border-color);
  padding: 0.4em 0.8em;
}
#sb-main .cm-editor .sb-table-widget th {
  font-weight: 600;
}

/* Widgets render as part of the page, not boxed */
#sb-main .cm-editor .sb-lua-directive-block {
  border-color: transparent;
}

/* Repo cards (front page and Repositories/<repo>) */
.docs-cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
  gap: 16px;
  margin: 8px 0 16px;
  font-family: var(--ui-font);
  line-height: 1.5;
}
.docs-card {
  display: flex;
  flex-direction: column;
  border: 1px solid var(--ui-surface-border-color);
  border-radius: 8px;
  background: var(--docs-card-background);
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.docs-card:hover {
  border-color: var(--docs-card-hover-border);
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.06);
}
.docs-card-body {
  flex: 1;
  padding: 16px 18px 12px;
  cursor: pointer;
}
.docs-card-title {
  font-size: 1.05em;
  font-weight: 600;
  color: var(--editor-heading-color);
  margin-bottom: 6px;
}
.docs-card-title::after {
  content: " →";
  color: var(--subtle-color);
  transition: margin-left 0.15s ease;
}
.docs-card:hover .docs-card-title::after {
  color: var(--ui-accent-color);
}
.docs-card-desc,
.docs-card-subject {
  font-size: 0.9em;
  color: var(--subtle-color);
}
.docs-card-desc p,
.docs-card-subject p {
  margin: 0;
}
.docs-card-subject {
  margin-top: 8px;
  font-style: italic;
}
.docs-card-footer {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 12px;
  padding: 10px 18px;
  border-top: 1px solid var(--ui-surface-border-color);
  font-size: 0.8em;
  color: var(--subtle-color);
}
.docs-card-commit {
  font-family: var(--docs-mono);
}
.docs-card-link {
  margin-left: auto;
  color: var(--ui-accent-color) !important;
  text-decoration: none;
}
.docs-card-link:hover {
  text-decoration: underline;
}
```
