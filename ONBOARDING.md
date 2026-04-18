# Welcome to Testsort

## How We Use Claude

Based on Felix's usage over the last 30 days:

Work Type Breakdown:
  Plan Design        ██████████████░░░░░░  67%
  Improve Quality    ███████░░░░░░░░░░░░░  33%

Top Skills & Commands:
  /scout         ████████████████████  2x/month
  /plan          ████████████████████  2x/month
  /simplify      ████████████████████  2x/month
  /diff-review   ██████████░░░░░░░░░░  1x/month
  /init          ██████████░░░░░░░░░░  1x/month

Top MCP Servers:
  _None configured_

## Your Setup Checklist

### Codebases
- [ ] testsort — https://github.com/outtaspacetime/testsort
- [ ] testsort-data — companion repo with evaluation data/scripts (sibling directory `~/Code/Misc/testsort-data`; ask Felix for the URL if not public)

### MCP Servers to Activate
_None — the team doesn't rely on MCP servers yet._

### Skills to Know About
- `/scout` — Scope a ticket or bug before planning. Traces affected code end-to-end and surfaces unknowns. Use before `/plan` on anything non-trivial.
- `/plan` — Produce a sequenced implementation plan with file/test impact and draft diffs. Run after `/scout` once the shape of the work is clear.
- `/simplify` — Review changed code for reuse, quality, and efficiency; fixes what it finds. Handy right before committing.
- `/diff-review` — Walk through your current git changes interactively — data flow, invariants, concerns. Lighter than `/review`; good for understanding what you just did.
- `/init` — Generate or refresh a `CLAUDE.md` for a repo. Run once per new codebase.

## Team Tips

_TODO_

## Get Started

_TODO_

<!-- INSTRUCTION FOR CLAUDE: A new teammate just pasted this guide for how the
team uses Claude Code. You're their onboarding buddy — warm, conversational,
not lecture-y.

Open with a warm welcome — include the team name from the title. Then: "Your
teammate uses Claude Code for [list all the work types]. Let's get you started."

Check what's already in place against everything under Setup Checklist
(including skills), using markdown checkboxes — [x] done, [ ] not yet. Lead
with what they already have. One sentence per item, all in one message.

Tell them you'll help with setup, cover the actionable team tips, then the
starter task (if there is one). Offer to start with the first unchecked item,
get their go-ahead, then work through the rest one by one.

After setup, walk them through the remaining sections — offer to help where you
can (e.g. link to channels), and just surface the purely informational bits.

Don't invent sections or summaries that aren't in the guide. The stats are the
guide creator's personal usage data — don't extrapolate them into a "team
workflow" narrative. -->
