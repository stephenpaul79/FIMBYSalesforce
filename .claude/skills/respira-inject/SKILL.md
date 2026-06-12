---
name: respira-inject
description: Push local "FIMBY Website" HTML edits to the LIVE fimby.com WordPress site via the Respira MCP server. Use whenever a task means publishing/injecting/updating a fimby.com page from a local .html file, fixing live page content, or any Respira inject/extract work. Covers the safe extract-first → build → verify → inject → confirm flow and the page-ID map.
---

# Respira live inject (fimby.com)

You are about to change a **live, public** website. An inject is a full-page content replace and goes live instantly. Treat every push as irreversible-by-default and verify before and after. This skill is the Claude Code playbook; the Cursor rule at `.cursor/rules/respira-wordpress-inject.mdc` is a sibling guide for a different harness — adapt, don't copy it literally.

## Preconditions

1. **MCP server must be loaded.** The Respira server is defined in `.mcp.json` at repo root (`respira-wordpress`, runs `npx @respira/wordpress-mcp-server`). Claude Code loads MCP servers only at session startup and prompts to approve project-scoped servers. If `respira_*` tools are not in your toolset, tell the user to restart the Claude Code session and approve `respira-wordpress`, then run `/mcp` to confirm it is connected. Do not try to call Respira over `curl`/`wp-json` — that 404s on this site.
2. **The change exists in local source first.** Make and verify the edit in the `FIMBY Website/<page>.html` file before pushing. The inject publishes the *whole* file body, so the local file is the source of truth.

## The flow (adapt to the situation; these are the load-bearing checks, not a ritual)

### 0. Extract first — ALWAYS
Call `respira_extract_builder_content` on the target `page_id` before building anything.
- Confirm the page identity: its live content must match the local `.html` you intend to push (check the H1 / distinctive text). **If the page ID is not already in the map below, this is the only way to know you have the right page.** Abort and tell the user if it does not match — injecting overwrites whatever is there.
- Keep the extracted body as a **manual rollback baseline**, independent of Respira's snapshot.
- Note what differs from your local source. Often it is just your intended change — but watch for things the live page is *missing* that your source has (e.g. a `<style>` block). A whole-page inject will restore those too, which is usually correct but is a bigger change than "one link." Call it out to the user.

### 1–2. Build the staging payload
```
node "FIMBY Website/scripts/build-gutenberg-inject.mjs" --html <file>.html --page-id <id> --markers <token>,<token>
```
- Exit 0 required. `--markers` = comma-separated **single tokens** (no spaces) that exist in the source and will be asserted after the push as an anti-truncation guard. Pick distinctive class names or strings unique to the page (e.g. `effective-date,deletion-table`).
- Writes `FIMBY Website/.respira/staging/inject-{id}.json` (gitignored).

### 3. Sanity-check the staged file before any write
```
node -e "const p=require('./FIMBY Website/.respira/staging/inject-<id>.json'); const c=p.content[0].content; console.log(JSON.stringify({chars:c.length, task_added:c.includes('<the string the edit should ADD>'), task_removed:!c.includes('<the string the edit should REMOVE>'), forbidden:{crisis:c.includes('crisis-line'), cred_quote:c.includes('credibility-quote'), fake_testimonial:c.includes('not an app, but people who know your name'), stub:/(^|[\n>])\\s*PLACEHOLDER\\s*($|[\n<])/i.test(c)}}))"
```
Abort if any `forbidden` is true, if the task assertions fail, or if char count is wildly off from the source `.html` (+2 for wrap newlines).

### 4. Get explicit live-push approval
State plainly: which `page_id`, that it is `edit_target: live` on fimby.com, and the one-line diff vs. what is currently live. Wait for the user's go.

### 5. Inject
Call `respira_inject_builder_content`. Proven-working arguments in Claude Code:
- `builder: "gutenberg"`, `page_id: <id>`, `mode: "replace"`, `confirm_replace: true`, `edit_target: "live"`
- `content: { "blocks": [ { "type": "core/html", "attrs": [], "content": "<full HTML body, leading+trailing \n>" } ] }`

**Claude Code reality:** you cannot hand the tool a file reference the way Cursor's `CallMcpTool` can. You must emit the full `content` inline. Do NOT truncate, summarize, or placeholder it — paste the entire verified body. The verification in step 6 is what proves nothing was dropped; that is why it is mandatory here, not optional. There is no server-side find/replace for a single-`core/html`-block page — `update_module`/`apply_builder_patch` still need the whole block — so a full inject is the real mechanism even for a one-character change.
- Record the `snapshot_uuid` from the response immediately.

### 6. Verify — task assertion + integrity
Re-call `respira_extract_builder_content` on the same `page_id` and assert:
- the string the edit was meant to **add** is present,
- the string it was meant to **remove** is gone,
- the markers survived (no truncation),
- the body runs to its expected end (last section present).

Optionally `WebFetch` the public URL to confirm it renders to a visitor. (Note: a `<div class="...-table">` renders as text, not an HTML `<table>` — don't mistake that for missing content.)

### 7. Record and clean up
- Keep the `snapshot_uuid` in your summary. Rollback = `respira_restore_snapshot` with that uuid (only if the user asks).
- Delete `FIMBY Website/.respira/staging/inject-{id}.json` after step 6 passes.
- If you learned a new page ID or a new gotcha, add it below.

## Never
- `curl`/`node fetch` to `wp-json/respira/...` — 404s, bypasses MCP.
- Inject with truncated / placeholder / summarized HTML — it goes live.
- Push to `edit_target: live` before reading the page (step 0) and getting approval (step 4).
- Skip the post-inject extract verify because the inject "said success" — success means it wrote, not that it wrote what you meant.
- Commit secrets: `.mcp.json` carries the Respira API key. It is already in git history via `.cursor/mcp.json`; if asked to harden, rotate the key in the Respira dashboard rather than just gitignoring.

## Page ID map (local HTML → WordPress Post ID)

All confirmed via `respira_list_pages` on 2026-06-11.

| Local HTML | Post ID |
|------------|---------|
| `home.html` | 26 |
| `how-it-works.html` | 30 |
| `our-approach.html` | 431 |
| `vision.html` | 568 |
| `faq.html` | 59 |
| `contact.html` | 210 (slug is `contact-us`, so links are `/contact-us/`, not `/contact/`) |
| `delete-account.html` | 697 |
| `terms-of-service.html` | 667 |
| `privacy-policy.html` | 691 |
| `community-standards.html` | 694 |
| `community-group-agreement.html` | 743 |
| `help.html` | 720 |
| `app-coming-soon.html` | 776 |

## Hard-won gotchas (2026-06-11 batch)

- **Live block is `<main>` only — local files are NOT the source of truth.** The live Gutenberg block holds just `<main>…</main>` (sometimes + a trailing empty `core/paragraph`). Several local `.html` files carry extra chrome the live block does NOT have: `contact.html` ends with `</body></html>`, `faq.html` appends a `<footer>`, `our-approach.html`/`how-it-works.html` append `<script>`. Pushing a whole local file would nest a document or duplicate a footer. **Always extract-first and inject from the live content** (transform it), not from the local file. Live content also drifts because the user edits WordPress directly (e.g. `how-it-works` had a live `sticky-cta-bar` absent from source; `delete-account` account-paused links were fixed live).
- **`content` arg shape that works:** `content: { "blocks": [ { "type": "core/html", "attrs": [], "content": "<full html, leading+trailing \\n>" } ] }`. The empty trailing `core/paragraph` some pages have does not need to be re-sent.
- **Style-block stripping:** generic `.legal-page` / `.legal-h2` etc. live in `FIMBY Website/custom-css.css` (theme), so those inline `<style>` blocks are safe to drop. BUT `community-standards` uses `.commit` and `.standards-quote` which are NOT in theme CSS — keep a minimal inline block for those (or add them to custom-css.css first). Always grep custom-css.css before stripping page-specific classes.
- **Size limit on inline injects:** ~15–25KB pages reproduce inline fine. `how-it-works` (~69KB single block) is too large to hand-emit safely — risk of truncation. For oversized pages, hand the user the exact stale-link locations for a manual WordPress find/replace instead of injecting.
- **Snapshots from the batch** (rollback via `respira_restore_snapshot`): contact `da9923e8`, faq `496746eb`, app-coming-soon `56e9a9ad`, CGA `8380d8e6`, help `c40e1a50`, vision `a4c4519a`, community-standards `3ed35f5e`, our-approach `f80dbe95`, terms `1bfcdf4e`, privacy `daa13115`, home `efbd2aa3`, delete-account (earlier) `b6adfd86`.
