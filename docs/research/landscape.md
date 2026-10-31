# Disk usage analyzer landscape: evidence teardown

Research date: 2026-10-31. Purpose: input to design of a native macOS disk analyzer. This file reports evidence only; it does not design the product.

## 0. Method, source quality, and gaps (read first)

**Labels used throughout**
- `[V]` verified this session from a fetched page, API response or tool output, with URL.
- `[V-abridged]` the fetch tool returned a paraphrased or truncated snippet of an HN/forum page. Wording is probably verbatim but fragments may be out of context.
- `[K]` prior knowledge, NOT re-verified this session. Treat as inferred.
- `[INFERRED]` my deduction from other evidence.

**What was actually mined (real user voice)**
- GitHub issues pulled verbatim through the `gh` CLI: `adileo/squirreldisk`, `bootandy/dust`, `imsnif/diskonaut`, `dundee/gdu`, `Byron/dua-cli`, `tbillington/kondo`, `shundhammer/qdirstat`, `windirstat/windirstat`. These are the highest-quality quotes in this file.
- Mac App Store review text for DaisyDisk (id 411643860) and GrandPerspective (id 1111570163), pulled from Apple's public RSS endpoint `https://itunes.apple.com/us/rss/customerreviews/page=1/id=<ID>/sortby=mostrecent/json` (about 50 most recent reviews each, one page only).
- Hacker News comments via the Algolia API and thread fetches; Apple Support Communities thread 256317534.
- Vendor pages (DaisyDisk, WizTree, SpaceSniffer) for features/price only.

**Gaps (be honest about what is missing)**
- **Reddit was not reachable.** WebFetch to reddit.com is blocked in this environment and WebSearch returned no Reddit threads. There is therefore zero direct Reddit quoting. This is the biggest hole; r/macapps, r/MacOS, r/mac, r/DataHoarder, r/sysadmin threads should be read by a human or a browser-enabled session.
- No App Store reviews for CleanMyMac X, TreeSize, OmniDiskSweeper (not on the App Store), Disk Inventory X (not on the App Store). CleanMyMac evidence is Trustpilot/PissedConsumer snippets via search results only `[V-abridged]`.
- "Radix" could not be identified as a disk analyzer; nothing verified under that name. Other recent entrants found are listed in section 1b.
- Baobab / Filelight evidence is from search-result summaries of old bug trackers, not read in full.
- Scan-speed numbers are almost all vendor claims; no independent benchmark was found for macOS tools.
- App Store RSS gives only the latest ~50 reviews per app, which skews toward recent and toward happy users (DaisyDisk). Absence of a complaint there is weak evidence.

---

## 1. Per-tool table

### 1a. Established tools

| Tool | Platform | Visualization | Scan speed claim | Killer feature | Top user complaints (with evidence) | Price |
|---|---|---|---|---|---|---|
| **DaisyDisk** | macOS | Sunburst rings | "Scan your disk in seconds, not minutes"; vendor chart shows 15 s vs Finder 1-6 min `[V]` daisydiskapp.com | Polish; Space-bar instant preview ("Hit Space on the keyboard to get an instant preview and identify any file"); counts hard links once, clone accounting (4.34, per a competitor blog `[V-abridged]`); snapshot management; cloud disk scan | No multi-select ("I wish you could multi-select though"; "removing several folders at a time can be tedious"); "It will not sort duplicate files or analyze old unnecessary files"; App Store build is sandboxed and cannot delete everything, users advised to use the standalone build; Sonoma slow-scan thread (MacRumors, search result only) | $9.99 one-time, up to 5 Macs `[V]` |
| **GrandPerspective** | macOS | Treemap (cushion gradients), colour by type/name/size/date | "Scans like a sprinter on my new M1" (user) | Free, 15+ years of loyalty, filters, hard-link support, export as image/text `[V-abridged]` | "Antiquated, slow, poor ux"; "Those harsh gradients are so unbelievably ugly"; "I don't get much out of a billion blobs. It only makes sense when you can immediately see file names and sizes"; scan freezes on Sonoma / epub files; App Store build lags behind the free build; no ignore-directory | Free (GPL) / $2.99 App Store `[V]` |
| **Disk Inventory X** | macOS | Treemap | n/a | Free, file-type colouring, SequoiaView lineage | Described as dated, slow development (reviews via search, `[V-abridged]`); original build was 32-bit `[K]` (a GrandPerspective review calls it "a previous ... 32-bit app") | Free |
| **OmniDiskSweeper** | macOS | None: sorted list | "Very fast" (Apple Communities reply) | Dead-simple sorted list, trash/open | Maintained slowly; no visuals. Fans prefer it: "drilling down through folders is just as easy as using a pie or wheel chart" (woodmeister50); "pie charts ... not as easy to read" (den.thed) | Free `[V-abridged]` |
| **CleanMyMac Space Lens** | macOS | Bubble map | "43 minutes to build my space map" in an early beta (TidBITS-linked review); another user: "it goes on forever" on an external drive `[V-abridged]` | Bundled in a cleaner suite | Space Lens design "has much to be desired" (TechRadar); complaints are mostly about the subscription and cancellation (Trustpilot/PissedConsumer) | Yearly subscription or one-time `[V-abridged]`; exact price not verified |
| **WizTree** | Windows | Treemap + file list | "46x faster than WinDirStat"; "does in seconds what similar applications take minutes" by reading the NTFS MFT directly `[V]` | MFT-speed scan; ubiquitous | Few user complaints found; WinDirStat users cite WizTree's on-tile labels as the standard to match (WinDirStat #583); "WizTree is no longer free for commercial use; bummer because it's really fast for NTFS" (password4321, HN) `[V-abridged]` | Free personal; commercial supporter code; amount not on page `[V]` |
| **WinDirStat** | Windows | Cushion treemap + tree + extension list | Recent versions have MFT "Accelerated scanning" per maintainers | The original; duplicate finder, Largest Files, search in 2.x `[V]` (issue #502 reply) | Treemap without labels (#583); folder visual hierarchy weak (#702, #633); UI freezes 16 min with 400k results (#743); "Very slow Progress after deleting 160 thousand files/dirs, cannot cancel" (#663); hard-link dedup "erroneously merges files" (#655) | Free (GPL) |
| **TreeSize (Free / Pro)** | Windows | Tree, charts; treemap | Faster than WinDirStat per reviews `[V-abridged]` | Reporting, Pro scheduling/network features `[K]` | Dua-cli user compares: "Slow scanning on Windows ... compare to other tools such as TreeSize free" (dua #302) | Free tier; Personal ~EUR 20.40/yr, Pro ~EUR 40.80/yr (sources conflict; verify) |
| **SpaceSniffer** | Windows | Nested treemap, live | Streams while scanning | **Tagging**: hover + `Ctrl+1` tags red (also yellow/green/blue), tags filterable/excludable; **filter language** like `*.jpg`, `>2years`, combined with `;` `[V]` uderzo.it | Dated Windows-only UI; the Linux user who wanted its look filed SquirrelDisk #50 | Free / donationware, portable `[V]` |
| **Baobab** (GNOME) | Linux | Ring chart / treemap | n/a | Ships with GNOME | Wanted individual files shown, not only directories: bugzilla 451393 (2009 request; "directories are sometimes smaller than single files in the same parent"; closed obsolete 2021) `[V-abridged]` | Free |
| **Filelight** (KDE) | Linux/Mac port | Concentric rings | n/a | Ring chart, the model for DaisyDisk-likes | Bug 122832 "Filelight ignores large files"; small files hidden at small window sizes; "show small files" option and thick border for hidden remainder `[V-abridged]` | Free |
| **QDirStat** | Linux/macOS/Win | Tree + treemap | Cache file for reload | Cleanup actions, hard-link logic, packages view, "locate" | **Dangerous delete** (see section 4); tiles are grey for files with no known extension (#271: "Wish: Colors of tiles - find a strategy for less gray"); "Different sizes among tools" (#302) | Free |
| **ncdu** | TUI | List with bars | Fast; HN: "extremely useful" | Ubiquitous, export format other tools reuse | Not installed on macOS by default (Apple Communities: suggesting it to novices "dangerous advise"); HN wishes: "optionally run off of a data file", "offline index" | Free |
| **gdu** | TUI | List + bars; web UI treemap | Goroutine-parallel, fast on SSD | `--since/--until` age filters (added in response to #504), trash command, web treemap | Wrong total with `-x` (#666); OneDrive online-only files still counted (#688); hardlink identity dropped in export (#667); wanted "highlight files that are safe to clean up" (#695) | Free |
| **dua-cli** | TUI | List, mark & batch delete | Very fast on macOS using `getattrlistbulk` `[V]` (issue #417) | Mark many then delete; `aggregate` | "export list of marked files" (#342); ignore-files (#327, 8 comments); scanning slow on Windows vs TreeSize (#302) | Free |
| **dust** | TUI/CLI | Compressed tree with bars | Fast | Shows largest files/dirs at any depth, not only directory totals | APFS clone double-counting (#590, still reproduces on 1.2.4/macOS 26.5.1); macOS privacy prompt stalls scan indefinitely (#546); "Dust never finishes" (#495, 23 comments) | Free |
| **diskonaut** | TUI | Terminal treemap | n/a | Zoom into treemap, delete | Small files hidden (#62); runaway memory (#65); numbers don't add up with hard links (#92); unmaintained (fork announcement #106) | Free |
| **Kondo** | CLI/GUI | Project list | n/a | Project-aware: finds `node_modules`, `target`, etc. and clears them | "Do not delete things in Library/Application Support" (#191); wants dry-run (#127), trash support (#96), ignore marker (#150) | Free |
| **SquirrelDisk** | Win/Mac/Linux (Tauri) | Sunburst (treemap added in 2.2) | Starts drawing before scan ends `[V-abridged]` | Free cross-platform DaisyDisk-alike; collect-and-delete | Many (see sections 2-4): sparse files, FDA clicks, rescans, "circle really hard to look", malware false-positive, maintainer seen as absent by forkers | Free |

### 1b. Recent entrants (2025-2026) found

| Tool | What it is | Evidence |
|---|---|---|
| **Klarity Disk** | $6.99 App Store DaisyDisk alternative | HN item 47014291 (Feb 2026, 1 point, 2 comments): the only stated differentiator is price; a commenter asked for real screenshots instead of a long scrolling landing page `[V-abridged]` |
| **Mole** (mole.fit) | Mac treemap analyzer plus free CLI `mo analyze --json`; one-time purchase | HN users praise it: "Yeah mole is brilliant, I just discovered it days after paying for Daisydisk and haven't used Daisydisk since" (columk). Note the vendor's own blog admits: "Attribution stays your job" and results are re-measured only after 6 h `[V-abridged]` |
| **DiskLens, DiskPrism** | Native macOS treemap/sunburst; DiskPrism "interactive treemap and linked columns" | Product Hunt / hunted.space listings only; not tested `[V-abridged]` |
| **Ansel** | OSS "Treemap + Sunburst file visualization, with folder depth visualization & a cleanup queue" | HN 48152178 author: "I often use DaisyDisk or Disk Inventory X when I need to clear space on my machine, I wanted more performance & features" `[V-abridged]` |
| **Leaves** | Rust TUI treemap | Show HN July 2026, 93 points, 31 comments `[V]` |
| **Disktree** | "A treemap for finding and removing what fills your disk" | HN 49841155, Sept 2026 `[V]` (title only) |
| **gp-treemap** | "GrandPerspective-style treemaps for the web and disk usage visualizer" | HN 47950902 `[V]` (title only) |
| **TamiaDisk, SQdisk** | Forks of SquirrelDisk created because users judged upstream neglected | squirreldisk #50, #64 `[V]` |

Observation `[INFERRED]`: the 2026 entrants compete on price, platform, or terminal rendering. None found markets keep/remove marking, semantic ignoring, or peer-level directory/file comparison.

---

## 2. Ranked unmet needs

Ranking is by (number of independent sources) x (severity: data loss or trust damage > daily friction > polish). "Independent" means separate people/threads/projects, not repeats in one thread. All counts are lower bounds from a limited sample.

### Rank 1. Safety: "what can I delete?" and not destroying things (about 10 sources)

The category maps and deletes, and leaves judgement to the user.
- "It maps and deletes ... does not know whether a folder belongs to an uninstalled app or whether a cache rebuilds. 'Attribution stays your job.'" (competitor blog, paraphrase) https://mole.fit/blog/daisydisk-alternative.md
- DaisyDisk reviewer, 2 stars: "You can DELETE things fast... but I wanted the program to show me what wasn't needed." https://itunes.apple.com/us/rss/customerreviews/page=1/id=411643860/sortby=mostrecent/json
- DaisyDisk reviewer: "So asked AI (Copilot) if it was safe to delete those files, and after AI said it was I deleted them and got back 21 GB." (user outsourcing the safety judgement to a chatbot) same URL.
- gdu #695: "I mostly use gdu to free disk space. In the treemap it would help to see right away which files and directories can be removed safely: build artifacts (node_modules, target), package caches (Go, Gradle, npm, uv), app caches, downloaded models, old installers." https://github.com/dundee/gdu/issues/695 (maintainer accepted and merged a PR).
- Apple Communities (woodmeister50): users "should only manage their user folder and Applications unless they know what they are doing." https://discussions.apple.com/thread/256317534
- Kondo #191 "Do not delete things in Library/Application Support"; #127 dry-run; #96 trash support. https://github.com/tbillington/kondo/issues
- QDirStat data-loss reports (section 4).
- HN, on AI-agent cache bloat: "There doesn't seem to be any sort of cleanup process in most apps that actually slims down their storage" (atonse) https://news.ycombinator.com/item?id=47219216 `[V-abridged]`
- DaisyDisk review: "Over 100GB of 'system data' that I couldn't make sense of. Somehow, it was the Podcasts app" (users want provenance: whose file is this).

### Rank 2. Sizes that do not reconcile with Finder / the volume (about 12 sources)

APFS clones, hard links, purgeable space, sparse files, compression, cloud placeholders, "System Data".
- SquirrelDisk #77: "Scanning the startup disk reports 832 GB, although the physical APFS container is only 494.4 GB". Maintainer's fix: count exact clones once, but "A clone that was modified after copying still counts in full, even if it shares part of its blocks with the origin." https://github.com/adileo/squirreldisk/issues/77
- dust #590: "Files that share physical blocks - APFS clones ... are counted at full size once per file ... inflates totals substantially"; maintainer: "Tricky ... definitely behind a separate flag." Still reproduces on dust 1.2.4 / macOS 26.5.1. https://github.com/bootandy/dust/issues/590
- SquirrelDisk #63 (Docker sparse image inflates), #39 ("orbstack use large sparse files (8TB!) ... It's not really 8TB big"), #41 (iCloud "determined as real size"), #74 ("Hidden Space" is "not a real folder", a synthetic remainder; reporter on a 4 TB drive with no permission issue still confused). https://github.com/adileo/squirreldisk/issues
- diskonaut #92 "Numbers aren't adding up" (hard links: "du says 95M but it's ~25 M because 4 files are hardlinked"), #26/#27 (compression, hard links), #95 (OneDrive on-demand files show full size). https://github.com/imsnif/diskonaut/issues
- gdu #688 (OneDrive online-only still counted), #666 (wrong total with `-x`).
- QDirStat #302 "Different sizes among tools" (reporter compares 556.1 GB vs 864.3 GB vs du/df); WinDirStat #747 (physical size ~8x logical for many small files), #655 (hard-link dedup merges the wrong files).
- DaisyDisk's own guide: Finder "wrongly counts each hard link as another copy"; compressed files counted by physical size; folders such as Photos can "appear empty or too small if you've denied DaisyDisk access." https://daisydiskapp.com/guide/4/en/FinderMismatch (the guide does not mention clones, purgeable or sparse).
- Eclectic Light: Finder's free/purgeable figures are unreliable on APFS and the relevant inode flags are not exposed to third parties `[V-abridged]` https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/
- DaisyDisk reviewers repeatedly describe the "System Data / Other" mystery as why they bought it ("Mac Storage Not Adding Up").

### Rank 3. Hiding or ignoring things: noise suppression (about 11 sources)

One giant item swamps the view; users want to hide it without lying to themselves.
- diskonaut #49: "a huge `target` directory completely swamping out everything else." https://github.com/imsnif/diskonaut/issues/49 (also #80, #93, #1).
- SquirrelDisk #39 "Ignore file", #41 (Gaugolon: "something like detecting a file .sqirrelignore ... and ignoring it permanently").
- GrandPerspective reviewer (4 stars): "I would give 5 stars if there was an ability to ignore particular directories and their children".
- dua #327 "Add ability to consume ignorefiles" (8 comments), #312, #277; dust #557 (rsync-filter syntax), #494 "how to exclude /home from /"; kondo #89 "How to ignore some directory?" (14 comments), #150; QDirStat #263 (ignored dir children bug).
- `[INFERRED]` Everything found is path/pattern based. No tool found ships semantic classes (for example "macOS system, hidden by default" vs "caches, shown") with a visible "N items hidden, X GB" ledger. The only semantic move found is gdu #695 colour-highlighting known caches.

### Rank 4. Marking / batch workflow, multi-select, review queue (about 9 sources)

- DaisyDisk reviews: "Support command select and shift select for several files"; "Great! I wish you could multi-select though."
- diskonaut #108 "multiple selector to erase groups"; #41 delete-key request (16 comments).
- dua #342 "export list of marked files"; gdu #504 "Advanced Delete" (delete all logs/installers older than X: "Using find or powershell ... is tedious"); gdu #640 trash command.
- SpaceSniffer coloured tags + tag filters are the only real marking system found `[V]`.
- Ansel's author built "a cleanup queue" because existing tools lacked one `[V-abridged]`.
- SquirrelDisk #34: "Is there an easy way to simply view the largest files on the system regardless of which directory they're in? I'd like to quickly eliminate some of the larger items without browsing through folders." https://github.com/adileo/squirreldisk/issues/34
- Absent entirely `[INFERRED]`: persistent keep/remove state that survives rescans, and an "undecided" backlog.

### Rank 5. Many small files are invisible or misleading (about 8 sources)

- diskonaut #62 (title "Bug: Small files hidden from view"); contributor: the cell showing "small files" is a "lie by omission" versus "abstracting away low importance information" https://github.com/imsnif/diskonaut/issues/62
- SquirrelDisk #40: "Show the number of total files/directories inside a directory, and allow sorting by that factor. This allows spotting directories with a large number of files, even when those files don't occupy a lot of space."
- WinDirStat #583: tiles below a 3 px threshold produce "artifacts of black sections"; #747: "folder with a large number of very small files ... Physical Size is almost 8 times the Logical Size" (cluster rounding makes small-file mass worse than it looks).
- QDirStat #271: default `MinTileSize=3`; setting `1` gives less grey "at the cost of rendering performance".
- Filelight changelog: "show small files" option plus thick border marking segments that hide unrepresented files; Baobab bugzilla 451393/586048 `[V-abridged]`.
- GrandPerspective review: "I don't get much out of a billion blobs."
- WinDirStat #502: requests grouping many sibling folders by common prefix/pattern.
- HN alexvoda on sunbursts: "circular distorted flame graphs and are of dubious utility" (related legibility critique).
- `[INFERRED]` Nobody found aggregates "the long tail" into a first-class, sized, inspectable object (count, bytes, age, type mix); every tool either drops it or paints it grey.

### Rank 6. Directory/file peer comparison (about 5 sources)

- dust #543 (contributor explaining why dust exists): "With ncdu/baobab/etc, these still just give you a view of directory sizes but you have no idea where the largest files are. For example directory A could have a size larger than directory B, but in fact the largest file is in B and not A." https://github.com/bootandy/dust/issues/543
- Baobab bugzilla 451393 (directories sometimes smaller than single files); Filelight bug 122832 ("ignores large files"); SquirrelDisk #34 (largest files regardless of directory); WinDirStat has a separate "Largest Files" tab (#502 reply).
- `[INFERRED]` The category treats files and directories as different species with separate views; the owner's "400 MB file vs 410 MB directory as peers" need matches this repeated friction. Nothing found offers a single ranked list or map that mixes both with a collapse/expand control.

### Rank 7. Rescan, freshness and persistence (about 8 sources)

- SquirrelDisk #83: "Would be great if the UI had an easy way to refresh/rescan a folder ... cmd+r"; #37 "Save/Load analysis".
- GrandPerspective reviewer: "after I have deleted some files from the finder and press refresh it complains about hard linked paths"; "it doesn't seem to save my recently selected path".
- HN (Leaves thread, `[V-abridged]`): "It would be helpful if it could optionally run off of a data file" (dunham); "What I really also want is a way to do an offline index that this reads" (rrauenza).
- dust #492 offline tree browsing; QDirStat #288/#292 cache-file reload bugs; WinDirStat #743, #663 (refresh/deletion freezes UI for minutes).
- DaisyDisk "very slow to scan in Sonoma" thread (MacRumors; developer attributes to a macOS privacy change, per search summary).

### Rank 8. Full Disk Access / permission friction and silent partial scans (about 8 sources)

- SquirrelDisk #70: "every protected directory will require a separate approval, which in my case made me click accept ~10 times." https://github.com/adileo/squirreldisk/issues/70
- dust #546: macOS privacy prompt "stalled indefinitely until the prompt is answered", even after excluding `/Users`. https://github.com/bootandy/dust/issues/546
- HN: "Disk scanning programs like DaisyDisk from the app store have to make you do this before they can get any information" (wlesieutre); "DaisyDisk - the version you download from them, not the one from the app store which has to be sandboxed" (nottorp) `[V-abridged]`
- DaisyDisk App Store reviews (three separate): "Get the website version for additional freedom to delete stuff you can't with the app store version"; "Get the std-alone ver ... full featured and better than one in App Store"; "I got the App Store version then transferred my license to the web download version and it allowed me to dig deeper into the huge 'System Data'".
- DaisyDisk guide: denied folders show as empty/too small. Competitor blog: "The danger is not the failure, it is the silence."
- Contradiction worth noting: one DaisyDisk user praised the first-run grant ("When you first buy it, you give the app permission to your drive and all your files"), so a single clear grant is acceptable; per-folder repeated prompts are what hurt.

### Rank 9. Preview before deciding (thin direct evidence: about 3 sources)

- Only DaisyDisk is documented to offer Space-bar preview (vendor page `[V]`).
- DaisyDisk reviewer: "People like me who do videos will have tons of files that are all named the same, but one may have 20 gigs of data. I have to sift through every file till I find the one that is eating up all the memory."
- HN (Leaves thread) bescob_ar: "One desire might be quick actions." `[V-abridged]`
- `[INFERRED]` Preview is a low-complaint area because users resort to Finder Quick Look; the absence of complaints is not evidence of satisfaction. No tool found supports video scrubbing, image comparison or similar-file grouping inside the analyzer. No source found specifically demanding in-app video playback; this need comes from the owner, not from the sampled corpus.

### Rank 10. Visual legibility and aesthetics (about 7 sources)

- SquirrelDisk #64 "The circle really hard to look" (macOS 26.4, light and dark); #50 request for a SpaceSniffer-style treemap because "I do not find the TreeMap [of QDirStat] as convenient, and not very beautiful."
- GrandPerspective: "Great utility, needs graphical refresh ... Those harsh gradients are so unbelievably ugly" and "Antiquated, slow, poor ux".
- WinDirStat #583 (no labels), #702/#633 (folder boundaries unclear); QDirStat #271 (too grey).
- Counter-evidence: DaisyDisk is described as "much more flashy and polished" (vasi, HN 2012) and by reviewers as "Beautifully presented", "Absolutely delightful". Looks are a real purchase driver at $9.99.
- Some users explicitly prefer plain lists over charts (OmniDiskSweeper fans above), so charts are not universally wanted `[V-abridged]`.

---

## 3. Interaction ideas worth stealing

**Inside the category (all sourced above)**
1. **SpaceSniffer coloured tags and filter language** (`>2years`, `*.jpg`, `;` to combine; tags filterable/excludable) https://www.uderzo.it/main_products/space_sniffer/index.html
2. **DaisyDisk Space-bar preview** and its collect-then-delete shelf `[K]` for the shelf (vendor page lists only preview).
3. **gdu #695 "safe to clean" colouring mode**: known caches highlighted, everything else grey, "Nothing is deleted automatically".
4. **gdu `--since/--until`** and dust's "largest at any depth" display: age and size slicing across directories.
5. **Filelight/diskonaut "files too small to render" remainder object** with a visible marker, plus diskonaut's zoom into it.
6. **Kondo's project awareness**: knows `node_modules`/`target`/`.next` are rebuildable; users still asked for dry-run and trash.
7. **WizTree MFT approach**: skip walking, read the catalogue (`[INFERRED]` macOS analogue is `getattrlistbulk`, which dua-cli already uses per its issue #417).
8. **Scan-reuse and data files**: ncdu export format reused by other tools; QDirStat cache files; HN requests for offline index.
9. **SquirrelDisk 2.5.1 clone handling** as precedent for "first one found pays, others are free" accounting, with the stated limit on partially modified clones.

**Outside the category (`[K]` unless a URL is given; none verified this session)**
1. **Photo culling tools (Photo Mechanic, Lightroom, Apple Photos, FastRawViewer)**: single-key Pick / Reject / Unflag, auto-advance to the next item, filmstrip plus loupe, survey and compare views for N similar items, filter bar showing only "unflagged" so the backlog shrinks to zero. This maps to the keep/remove marking need and the "N undecided" progress metaphor.
2. **Command palettes (Raycast, VS Code, Linear)**: fuzzy "go to / do anything", recent items first, verbs and filters as typed tokens (for example "older than 1y in Caches"). Matches the filter-language idea from SpaceSniffer without a settings dialog.
3. **Finder Quick Look and Spotlight smart folders / saved searches**: preview on Space, saved queries as durable "views".
4. **Git staging area and dry-run**: marking is a staged change set you review as a diff before a commit; mirrors kondo #127 (dry-run) and gdu #640 (trash).
5. **Undoable delete (Trash with Put Back, Gmail "undo send")**: reversibility instead of repeated confirmation dialogs. QDirStat's maintainer argues warnings do not work ("More warnings are completely useless when users already ignore the first one"), which supports reversibility over warnings. https://github.com/shundhammer/qdirstat/issues/293
6. **Time Machine local snapshots / APFS snapshots** as the safety net users already half-understand; DaisyDisk offers snapshot management `[V]`.
7. **Disk-usage "treemap with labels"** from SequoiaView lineage: labels directly on tiles is the most repeated treemap ask (WinDirStat #583).

---

## 4. What makes users distrust or uninstall these tools

**1. Deleting more than intended (highest severity)**
- QDirStat #316 "QDirStat wiped my home directory": selected two folders in `.cache` with Ctrl+click and saw `rm -rf /home/[user]`. The maintainer replied the startup selection is the scan root and Shift-click can extend from a hidden anchor. https://github.com/shundhammer/qdirstat/issues/316
- QDirStat #267: selecting subfolders plus an ancestor deletes the parent; #293: "inadvertently deleted a folder that had over 100GB"; #329 (2026): "Shift-click range extends from a hidden tree-view anchor left on the scan root ... then runs rm -rf on the scan root and sibling directories that were never highlighted." https://github.com/shundhammer/qdirstat/issues/329
- The maintainer's stance: the delete menu already says "no way to undelete!" and more dialogs "teach them to click blindly". Lesson from this dispute `[INFERRED]`: the failure is invisible selection state, not missing warnings.
- GrandPerspective App Store, 1 star: "Will destroy your files ... the file I wanted to open gave the error ... damaged and can't be opened. Grand Perspective showed as the last program to modify that file." Unverified single claim; included as evidence of how a read-only tool gets blamed.

**2. Totals that look impossible**: a disk "larger than the physical disk" (#77), "Numbers aren't adding up" (diskonaut #92), mystery "Hidden Space" remainder (#74). Users conclude the tool is lying, even when it is technically right.

**3. Silent partial results**: permission-denied folders drawn as empty or small (DaisyDisk guide; "The danger is not the failure, it is the silence"); scans that stall at 100% (SquirrelDisk #60) or three-quarters (GrandPerspective review "Scanning stalls 3/4 way through"), or "Never shows scan results" (#42, 8 comments).

**4. Malware or ad suspicion**: SquirrelDisk #62 "Possibly malware found in SquirrelDisk 0.3.4" (Intego flag; maintainer: false detection, warns of "repacked" copies on other sites); #44 "Make Headway App integration opt-in" (title only read); #71 "Request for AI Disclosure" (title only read). A DaisyDisk reviewer complains of a "Tweet it!" button ("big yikes"). Disk tools need broad file access, so any telemetry or sketchy distribution is punished.

**5. Subscription and cleaner-suite behaviour**: CleanMyMac complaints are dominated by subscription and cancellation ("canceled my subscription months ago but they keep debiting my account", Trustpilot snippet `[V-abridged]`). Contrast: DaisyDisk's one-time price is the first thing satisfied reviewers mention ("10 bucks once vs. a 5-10$ payment forever"; "Servant of Cats": people "ought to be willing to pay $10"). HN: "(I personally use DaisyDisk but that requires a license)".

**6. Abandonment**: SquirrelDisk forked twice by users who saw it as neglected (TamiaDisk, SQdisk); GrandPerspective "App Store version not updated ... Developer doesn't seem to care"; diskonaut fork announcement (#106); Disk Inventory X "dated"; OmniDiskSweeper "maintained slowly". macOS releases (Sonoma privacy checks, Tahoe 26) repeatedly break scanners.

**7. Two builds, different powers**: the App Store build cannot do what the website build can (sandbox), and users must learn this after paying. Source: three DaisyDisk reviews and two HN comments above.

**8. Refund friction**: 1-star DaisyDisk review: "The 30 day money back guarantee on the website is a lie ... Apple denied the refund" (single review; indicates what happens when a user buys the App Store build, then reads website terms).

**9. Performance cliffs and lockups**: WinDirStat froze 16 minutes at 400k results (#743); dust "never finishes" (#495); diskonaut runaway memory (#65); SquirrelDisk #81 "Utilizing too much GPU (60% of 4070 Ti Super)". Non-cancellable long operations (WinDirStat #663) are specifically resented.

---

## 5. Source index (key URLs)

- SquirrelDisk issues: https://github.com/adileo/squirreldisk/issues (#34, #37, #39, #40, #41, #44, #50, #60, #62, #63, #64, #70, #71, #74, #77, #83)
- dust: https://github.com/bootandy/dust/issues/590, /543, /546, /495, /517
- diskonaut: https://github.com/imsnif/diskonaut/issues/62, /49, /92, /108, /41, /26, /27
- gdu: https://github.com/dundee/gdu/issues/695, /504, /688, /666, /667
- dua-cli: https://github.com/Byron/dua-cli/issues/342, /327, /302, /417
- kondo: https://github.com/tbillington/kondo/issues/191, /127, /96, /89
- QDirStat: https://github.com/shundhammer/qdirstat/issues/316, /329, /293, /267, /271, /302
- WinDirStat: https://github.com/windirstat/windirstat/issues/583, /502, /702, /743, /663, /655, /747
- DaisyDisk App Store reviews (RSS): https://itunes.apple.com/us/rss/customerreviews/page=1/id=411643860/sortby=mostrecent/json
- GrandPerspective App Store reviews (RSS): https://itunes.apple.com/us/rss/customerreviews/page=1/id=1111570163/sortby=mostrecent/json
- DaisyDisk: https://daisydiskapp.com/ and https://daisydiskapp.com/guide/4/en/FinderMismatch
- WizTree: https://diskanalyzer.com/ ; SpaceSniffer: https://www.uderzo.it/main_products/space_sniffer/index.html
- HN: Leaves https://news.ycombinator.com/item?id=48936389 ; Klarity Disk https://news.ycombinator.com/item?id=47014291 ; Cowork VM thread https://news.ycombinator.com/item?id=47219216 ; Algolia comment search for "DaisyDisk" and "GrandPerspective" (items 8899245, 46763796, 43174239, 4123919, 33894863, 40456945, 36875905)
- Apple Communities: https://discussions.apple.com/thread/256317534
- Competitor blog (marketing, discount accordingly): https://mole.fit/blog/daisydisk-alternative.md
- Eclectic Light on Finder sizes: https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/
