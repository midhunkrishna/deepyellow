# DeepYellow: product and UX design

A native macOS disk analyzer built around one sentence:

> **See what's on your disk, understand it at the right level of detail, and clear it without fear.**

Evidence lives in `docs/research/`: `landscape.md` (what users complain about), `ux-principles.md` (HCI literature), `reclaim-kb.md` (macOS facts). Tuning values such as animation durations are our own choices, not research findings.

## 1. What the research changed

| Finding | Consequence here |
|---|---|
| The worst failures are invisible selection state ("wiped my home directory"), not missing warnings | Marking is staged like `git add`. The staged total is always on screen. Nothing touches disk until an explicit Apply, and Apply only moves to Trash |
| Totals that look impossible make users think the tool is lying | The **Ledger** reconciles every byte against the volume, with an explanation of why it differs from Finder |
| "No tool says what's safe to delete" is the top unmet need | Every item carries a safety tier with its consequence in plain words. Uncertain is `review`, never rounded up to `safe` |
| Treemaps win for file-vs-directory comparison and above ~2–4k items; bars win for hundreds; radial is liked but weak at comparing sizes | Map is primary, Things (bars) sits beside it, Rings exists but isn't the default |
| Comparing squares degrades accuracy; extreme ratios hurt | Layout targets moderate ratios (around 3:2), not squares |
| +500 ms latency measurably reduces exploration, with carryover | Budgets: hover ≤ 1 frame, filter ≤ 100 ms, navigation ≤ 1 s. Scans are interactive from the first second |
| GPU-burning visualizers get complaints | Render on demand. **Idle is zero GPU** |
| Disk tools need broad access, so any telemetry is punished | No network code at all. Say so in the UI |

## 2. The core ideas

### 2.1 Gold means reclaimable
The name is the visual system. The canvas is warm near-black, kinds are muted jewel tones, and deep yellow is reserved for exactly one meaning: *space you could get back* (plus focus). In Safety colour mode the whole map goes dark except what's safe to remove, which glows gold. You see your answer before reading anything.

### 2.2 Things, not files or folders (the directory-abstraction problem)
Your example, a 400 MB file next to a 410 MB directory, is something no tool we found can show in one ranked list (dust issue #543 asks for it). Trees force you to choose a depth; flat lists force you to choose files.

**Things** cuts the tree at a size threshold `T` instead of at a depth:
- A file or directory is listed as one thing when it's at least `T` and can't be split into anything else at least `T`.
- A directory with a big child gets split, and whatever is left is rolled into "N smaller items in X", or carried upward if that's still under `T`.
- The result is **disjoint and adds up exactly to the total**, so nothing is counted twice and nothing vanishes.

One slider sets the level of detail, from "your disk is 12 things" to "your disk is 4,000 things". At `T = 400 MB`, your file and your directory are neighbouring rows. Semantic atoms (`node_modules`, `.git`, `.app`, `DerivedData`, `.venv`, `target`, packages) stay whole until you ask to open them, because that's how people think about them.

### 2.3 Honest dust (the small-files problem)
Most tools drop small files or paint them grey, which users call "lying by omission". Here:
- Tiles too small to see merge into a **dust tile** per directory, rendered as literal stippled dust whose density reflects the count, labelled "12,431 small files · 3.1 GB".
- Zooming into dust continues the map. Layout is recursive, so dust resolves into tiles at any depth.
- Press `m` to switch any view between **bytes** and **file count**. Swarms invisible by bytes become giants by count.
- **Spectrum** shows the shape directly: count and bytes per size range, plus "the top 40 items hold 80% of your disk".

### 2.4 Decide like a photo editor
Culling photos is the closest solved problem to this. Single-key verdicts, auto-advance, and a backlog that shrinks to zero.
- `k` keep, `x` remove, `l` later, `u` clear, from any view, on any selection. `⌘Z` undoes.
- **Review** (`r`) takes the current set (any selection, query or Reclaim family) full-screen: large preview, filmstrip, verdict keys, "38 left · 214 GB decided". The next item is preloaded, so advancing is instant.
- Decisions inherit downward and the deepest wins. Keeping one file inside a directory marked remove is a first-class state, shown as partial.
- Decisions persist across scans, keyed by path with a fingerprint. If a file changes after you judged it, the verdict is flagged stale and is not applied.
- Keep is the default. Nothing is ever pre-marked for removal.

### 2.5 Apply is a diff, not a dialog
No per-item "Are you sure?" dialogs, because they teach blind clicking. `⌘⏎` opens the **Plan**: the exact list of roots to be moved to Trash, what's protected inside them, what's blocked and why, and the honest estimate ("frees at least 41.2 GB"). Apply moves to Trash, with one-step undo that puts everything back. The app never deletes permanently, and states plainly that Trash frees nothing until emptied.

### 2.6 Hidden, never gone
Ignore rules hide things from views but never from accounting. The Ledger always shows "Hidden: 18.2 GB in 41,204 files", and it opens to per-rule totals. macOS plumbing is hidden by default; `~/Library/Caches` is explicitly kept visible. Rules apply instantly with no rescan: right-click for "Hide this", "Hide all named X" or "Hide all .ext", each with a toast offering Undo.

## 3. The screen

```
┌─ ◐ Macintosh HD › Users › demo › Movies        [ / query…          ]   Map Things Spectrum Field Rings Browse Reclaim ─┐
│                                                                                                                         │
│                                   full-bleed canvas: the current lens                                     ┌ preview ┐  │
│                                                                                                           │ on Space│  │
│                                                                                                           └─────────┘  │
├─ LEDGER ▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▒▒▒▒░░░░     312 GB visible · 18 GB hidden · 3 unreadable · 88 GB free    ▨ 41 GB staged ⌘⏎ ─┤
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

The chrome is one thin top line and one thin bottom line; the data gets everything else. No sidebar, and panels appear only when summoned. Holding `⌥` overlays every shortcut on the UI, so mouse users graduate to keys without studying anything.

The **Ledger** is the trust anchor. It's a single bar of the whole volume: visible, hidden, unreadable or unaccounted, free. Staged removal is hatched over the top. Click it for the reconciliation: logical vs allocated, hard-link and clone savings, snapshots and purgeable, and a labelled remainder.

## 4. Seven lenses and a mode

Every lens reads the same `TreeLens`, shares one selection and one query, and is one keystroke away. Switching keeps your focus and selection.

| Key | Lens | The question it answers | Form |
|---|---|---|---|
| `1` | **Map** | Where did it all go? | Continuously zoomable treemap with labels on tiles, nested directory headers and dust. World-space layout never reflows while zooming, so you keep your bearings. |
| `2` | **Things** | What are the biggest things? | The threshold-cut ranked list with the granularity slider and a cumulative-share rail. |
| `3` | **Spectrum** | What shape is my disk? | Size histogram in human decades, count and bytes as separate small multiples (never dual-axis), plus a cumulative share curve. Brush to filter. |
| `4` | **Field** | What's old, big and forgotten? | Every file as a point of light: age × size, additive blending, like a star field. The old-and-big corner is where the gold is. Brush to filter. |
| `5` | **Rings** | How is it nested? | Sunburst for hierarchy, loved at first sight and useful for structure. Sizes are read from labels and the HUD. |
| `6` | **Browse** | Where is that thing I know about? | Miller columns with inline size bars, for Finder natives. Fully keyboard-driven. |
| `7` | **Reclaim** | What can I remove safely? | Rule families grouped by tier: consequence, staleness and the official cleanup command. One decision can cover hundreds of items. Includes duplicates. |
| `r` | **Review** | Should this go? | Full-screen culling over the current set. A mode, not a lens. |

**Colour modes** (`c`), available in Map, Rings and Field: Kind, Age, Safety, Decision.

**Query** (`/`) is one language everywhere: `size>100mb age>1y kind:video -path:Photos ext:mov,mp4 is:clone mark:remove safe:safe`. A bare word matches name or path. It filters every lens live. Brushing Spectrum or Field writes into the query, so it stays visible and editable.

**Palette** (`⌘K`) reaches every command and jumps to an exact path you type or paste, with recents first. It has no fuzzy path search and no saved queries.

**HUD on hover** gives strong information scent within one frame: name, size, share of parent, last modified, file count, safety and why.

### Keyboard
| Key | Action | Key | Action |
|---|---|---|---|
| `1`–`7` | Switch lens | `k` `x` `l` `u` | Keep, remove, later, clear |
| `Space` | Toggle preview | `r` | Review current set |
| `⏎` / `⌫` | Go in / zoom out | `⌘⏎` | Open the Plan |
| `←↑↓→` | Move selection | `⌘Z` / `⇧⌘Z` | Undo / redo |
| `/` | Focus query | `h` | Hide selection |
| `⌘K` | Palette | `m` / `c` | Metric / colour mode |
| `⌥` (hold) | Show all shortcuts | `Esc` | Back out one level |

## 5. Preview
`Space` opens a right-hand pane from any lens, and arrow keys keep working underneath it. Video plays with a filmstrip scrubber, and hover scrubs. Images decode to screen size at once, with smooth pan and zoom. Audio shows a waveform. PDFs and text render natively, and everything else falls back to QuickLook. A directory shows a composition of its largest children. iCloud placeholders are never downloaded by accident: they show metadata and a Download button.

## 6. Motion and looks
- Warm near-black canvas, soft cushion lighting, 1 px gaps, rounded tiles, SF Pro with tabular SF Mono numerals.
- Springy zoom around 280 ms, cross-fades on lens switches, tweened re-layout by node identity. Respects Reduce Motion.
- During a scan the map grows live, with a quiet gold shimmer on the directories being read and a live file rate.
- State is never colour alone: remove is a hatch, keep is a pin, later is a dot.
- Dark only in v1, chosen deliberately: the visual concept depends on it.

## 7. Trust rules (non-negotiable)
1. No network code, no telemetry, no analytics.
2. The app never permanently deletes anything. Trash only.
3. The scan root, home, top-level system folders and SIP-protected items can never be planned for removal, whatever is selected.
4. There's no hidden selection anchor. Everything acted on is visibly selected, and the count and bytes are on screen.
5. Scans never silently under-report: unreadable directories are counted and shown, and missing Full Disk Access is stated up front.
6. Reading a file never downloads it (dataless guard) and never modifies it.
7. Advice uses the `reclaim-kb.md` tiers. Evidence-limited items stay at `review`.

## 8. Not in v1
Light mode; subtree rescan and live FSEvents updates; growth-since-last-scan comparison; running cleanup commands (they're shown, not run); network volumes as a tested target; Developer ID notarization.
