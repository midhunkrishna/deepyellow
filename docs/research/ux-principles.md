# UX and Information-Visualization Principles for a Disk Usage Analyzer

Research digest for the native macOS disk analyzer. Date: 2026-10-31.

## How to read this document

Every entry follows **Finding -> Source -> Implication**. Evidence is graded:

- **[Verified]** I read the text of the source (or its abstract/project page) in this session and the number or claim is quoted from it.
- **[Secondary]** I found the claim only in a secondary page that cites the source. Treat as a lead, not a fact.
- **[Not fetched]** The source is well known, but I did not retrieve it in this session. I name it for follow-up and state no result from it.
- **(inferred)** My design inference. It is not something the source says.

Caveats up front:

- Several results rest on crowdsourced (MTurk) studies with fixed 600x400 px stimuli. A native Retina app is a different viewing condition (Kong et al. say so themselves).
- Where the literature has no number, none is invented. See "Gaps" at the end.

---

## 1. Treemaps and space-filling layouts

### 1.1 Aspect ratio matters; squares are not the goal
- **Finding.** Luminance does not affect area judgements. Aspect ratio does: accuracy suffers when compared rectangles have extreme aspect ratios, or when both are squares. "Contrary to common assumptions, the optimal distribution of rectangle aspect ratios within a treemap should include non-squares, but should avoid extremes." The authors suggest a layout optimising toward a moderate non-unity ratio (the PDF text extraction renders it as "3 2", likely 3:2 - inferred) might beat squarified layouts. Squarified layouts still beat slice-and-dice, because squarify cannot actually reach all-square.
- **Source.** Kong, Heer, Agrawala, "Perceptual Guidelines for Creating Rectangular Treemaps", IEEE TVCG 16(6), 2010. [Verified, full text read] https://idl.uw.edu/papers/perception-treemaps and https://homes.cs.washington.edu/~jheer/files/treemaps.pdf
- **Implication.** Use squarified (or a variant) as the base layout, and expose aspect ratio as a layout quality metric in tests. Do not "fix" leftover non-square cells. Reject slice-and-dice for the main view. A custom layout targeting about 1.5:1 is a research bet, not a proven win (inferred).

### 1.2 Treemaps vs bars: density decides
- **Finding.** Hierarchical bar charts had lower error for leaf comparison at low density ("a few hundred elements"). Treemaps and bars were equally fast up to 2048 leaves. Treemap accuracy matched bar accuracy beyond 4096 leaves, where treemaps were almost 3 s faster. At 8000 leaves treemaps were almost 5 s faster. For comparisons involving non-leaf (directory) nodes, treemaps were more accurate at all densities (mean log error 3.24 vs 3.62 node-vs-node; 2.14 vs 2.61 leaf-vs-node). Luminance can encode a secondary variable without hurting area judgement.
- **Source.** Kong et al. 2010, sections 6 and 7 [Verified], same URLs as 1.1. Cited inside: Stevens exponents for judgement are about 1 for length and about 0.7 for area.
- **Implication.**
  - Directory-vs-file comparison (hard problem b) is exactly the case where treemaps beat bars. Keep a treemap as a primary view.
  - For the top-N list (say <= about 200 items) offer a ranked bar list as a coordinated second view. It is more accurate for exact size comparison.
  - Colour (luminance) can safely carry age or "last opened" without corrupting size perception.
  - Caveat: the data are for two-level trees with random values, not real file systems (the paper lists this as a limitation).

### 1.3 Treemap vs sunburst on file hierarchies
- **Finding.** In two studies (60 participants across both), performance trends favoured Sunburst on correct task performance, especially on first use. Treemap improved with practice ("a greater learning cost that was partially recouped"). 51 of 60 favoured Sunburst, 8 Treemap, 1 unsure. Participants cited better conveyance of structure. About two-thirds said Treemap would be better for file size comparison, and Sunburst users were frustrated comparing sizes by angle.
- **Source.** Stasko, Catrambone, Guzdial, McDonald, "An evaluation of space-filling information visualizations for depicting hierarchical structures", IJHCS 53, 2000. [Verified, full text read] https://faculty.cc.gatech.edu/~john.stasko/papers/ijhcs00.pdf
- **Implication.**
  - Preference and learnability favour radial; precise size comparison favours rectangles. Neither dominates, so offer both as views over one dataset, with rectangles as the decision surface and radial as the orientation/overview surface (inferred).
  - Sunburst's known weakness is tiny peripheral items in big hierarchies (stated in the paper, and the reason Stasko and Zhang added focus+context). Cap sunburst depth (for example 4-5 rings visible, deeper on zoom) (inferred).
  - Small samples and 2000-era file trees: treat as directional.

### 1.4 Squarified, cushion, ordered, Voronoi, zoomable
- **Finding (squarified).** Squarify adds rectangles to a row while the worst aspect ratio improves, then starts a new row. Wikipedia's treemap page notes the trade-off: optimising aspect ratio makes placement order less predictable, while stable order degrades aspect ratio. [Secondary] https://classes.engineering.wustl.edu/cse557/readings/squarified-treemap.pdf (Bruls, Huizing, van Wijk, Data Visualization 2000; the PDF host was returned by search, the full text was not read).
- **Finding (stability).** Stable Voronoi treemaps exist: Hahn, Trümper, Moritz, Döllner (IVAPP 2014) give a deterministic initial distribution to reduce positional variation when the hierarchy changes. A 2017 paper proposes "Relative Direction Change" as a stability metric. [Secondary, abstracts only] https://www.scitepress.org/Papers/2014/46862/ , https://www.scitepress.org/Papers/2017/61175/
- **Not fetched.** Shneiderman 1992 (original treemap), van Wijk and van de Wetering 1999 (cushion treemaps), Blanch and Lecolinet 2007 (zoomable treemaps), Bederson/Shneiderman/Wattenberg 2002 (ordered/quantum treemaps; Kong cites it as an ordering-enforcing alternative). I state no result from them.
- **Implication.**
  - A disk tool re-layouts constantly (deletes, scans in progress, zoom). Layout stability is a first-class requirement: removing one file should move neighbours as little as possible. Choose an ordered or incremental-stable layout over pure squarify for the live view, and measure stability with a metric such as relative direction change (inferred).
  - Cushion shading (the WinDirStat look) is well-known but I did not read the source. Kong found luminance does not distort area judgement, which suggests subtle shading is safe, but this does not directly test cushion shading (inferred).

---

## 2. The small-item problem (long tails)

### 2.1 What the literature gave me
- **Treemap density limit.** Kong et al. tested up to 8000 leaves in 600x400 px, about 30 px^2 per leaf, and accuracy degraded with density for both chart types [Verified]. Anything beyond that is below the tested regime (inferred).
- **Log scales and laypeople.** In a roughly 2000-person US sample, a basic comprehension question was answered correctly by 40.66% with a log-scale chart versus 83.79% with linear. A Sage-published study found lay viewers were less accurate at predicting growth, and education reduced but did not eliminate the effect. Other studies conflict: one found scale had no impact, another found log produced more errors describing the graph while linear misled when extrapolating exponential growth. [Secondary, search summaries] https://blogs.lse.ac.uk/covid19/2020/05/19/the-public-doesnt-understand-logarithmic-graphs-often-used-to-portray-covid-19 , https://journals.sagepub.com/doi/10.1177/237946152000600203
- **Implication.**
  - Never use a log axis silently. If a log histogram is used (file-size distribution), label decades in human units ("1 KB, 1 MB, 1 GB") and show the area/count each bucket represents.
  - Prefer a **cumulative "share of space" curve** (Lorenz/Pareto: "the top 50 files are 31% of used space") over log charts for laypeople, because it needs no axis literacy (inferred; I did not find a study of Lorenz comprehension).
  - The size histogram plus cumulative curve answer "where is the weight?" in one glance, which is the decision-driving question (inferred).

### 2.2 Aggregation design
- **Not fetched.** Card and Nation, "Degree-of-Interest Trees" (AVI 2002); Heer and Card, DOITree (2004); Grosjean, Plaisant, Bederson, SpaceTree (2002); Furnas, "Generalized fisheye views" (1986). I state no results.
- **Implication (inferred from the concepts, not from numbers).**
  - Aggregate small items into a labelled "N small items, X GB" cell per directory, whose size is honest (sum) and which is a first-class interactive object: click to expand, select to act on all.
  - Use a degree-of-interest score combining size, recency, and user focus to decide what to show, rather than a fixed size cutoff. This is the core DOI idea.
  - Minimum visible cell: choose a pixel floor (for example 4x4 logical px; this is my number, not literature's) below which items are folded into the parent's aggregate cell.
  - Millions of files cannot be drawn as individual marks. Density-based rendering (Section 3.3) applies to scatter-style views only.

### 2.3 Focus + context and semantic zoom
- A search summary of Stasko and Zhang (InfoVis 2000) says they added focus+context techniques because peripheral sunburst items are tiny [Secondary; paper not read]. No numbers on semantic zoom were fetched.
- **Implication (inferred).** Zoom should change what is drawn (names, file-type breakdown, aggregate cells expand to items), not just scale. Keep the ancestors visible as a breadcrumb or "pinned context" so the viewer never loses where a zoomed directory sits.

---

## 3. Coordinated views, brushing and linking, latency

### 3.1 Latency thresholds
- **Finding.** Liu and Heer added 500 ms to brushing-and-linking operations (baseline about 20 ms vs about 520 ms). The extra delay "incurs significant costs, decreasing user activity and data set coverage", and lowered observation, generalisation and hypothesis rates in think-aloud data. Brushing and range-selection rates fell; zoom and pan rates were not significantly affected. Initial exposure to delay reduced performance in a later low-latency session (carryover). The paper's Card et al. table: about 100 ms "perceptual fusion" (tracking animation, brushing), about 1 s "unprepared response" (click a link), about 10 s "unit task". Card et al. place brushing and linking in the 100 ms band.
- **Source.** Liu and Heer, "The Effects of Interactive Latency on Exploratory Visual Analysis", IEEE TVCG 20(12), InfoVis 2014. [Verified, full text read] https://idl.uw.edu/papers/latency , https://mail.zcliu.cs.umd.edu/latency/latency-InfoVis.pdf
- **Caveat.** A replication (Zgraggen et al.) is reported [Secondary] to find negative effects at high latency but no consistent differences between 6 s and 12 s delays.
- **Implication.**
  - Budget: hover/brush/link updates <= 100 ms end to end, ideally one frame (16 ms at 60 Hz, 8 ms at 120 Hz ProMotion). Navigate/zoom/open <= 1 s with visible progress. Anything longer than about 10 s needs a progress UI and must be cancellable.
  - Zoom and pan are more latency-tolerant than brushing (Liu and Heer), so spend optimisation effort on cross-view highlighting and selection first (inferred).
  - Carryover means a slow first impression harms the whole session. Make the first scan result interactive early (progressive display) (inferred).

### 3.2 Scalable linked views
- **Finding.** Falcon (Moritz, Howe, Heer, CHI 2019) reports about 50 fps pixel-level brushing across several linked views, constant brushing time regardless of data size (millions in browser to billions on a database), by re-indexing on the active view and progressively refining resolution. [Secondary: abstract/project pages] https://idl.uw.edu/papers/falcon
- **Implication.** Precompute per-view aggregate indexes (size by type, by age, by directory) so cross-filtering is a lookup rather than a rescan. Index the *active* view's dimension at full resolution and the others coarsely, refining after the brush stops (inferred from Falcon's design).
- **Not fetched.** Crossfilter, Imme (Chen et al.). No claims made.

### 3.3 Overplotting
- **Not fetched** (no source retrieved on density plots or binned scatter). Standard practice I am applying by inference: for scatter-style views (size vs age for millions of files) bin to a 2D grid and map count to a perceptually uniform sequential colour scale, with log-ish count mapping disclosed on the legend, rather than drawing individual points.

---

## 4. Information foraging and the mantra

### 4.1 Information foraging
- **Finding.** Pirolli and Card (Psychological Review 106(4), 1999): people seeking information behave like foragers. Core constructs: **patches** (clusters of information), **information scent** (imperfect perception of value, cost or access path from proximal cues such as labels or icons), **diet** (add a patch type only if it beats the average gain rate), and a patch-leaving rule (leave when the within-patch gain rate falls to the average rate; Charnov's marginal value theorem). [Secondary: abstract-level summaries] https://ixdf.org/literature/book/the-glossary-of-human-computer-interaction/information-foraging-theory
- **Implication (inferred).**
  - A directory is a patch. Its treemap cell label is its scent. A cell that says only "Library" has weak scent; "Library: 41 GB, 38 GB is Caches, untouched 14 months" has strong scent. Put the most decision-relevant summary on the cell or its hover card.
  - The tool should surface the highest "gain per effort" patches first (big, old, regenerable), because that is where the user's time is best spent. A ranked "biggest wins" list operationalises diet selection.
  - Show diminishing returns: "the next 100 items would free 0.3 GB". It tells the user when to stop foraging.

### 4.2 Shneiderman's mantra and critiques
- **Finding.** The mantra is "overview first, zoom and filter, then details-on-demand" (Shneiderman, "The eyes have it", 1996; [Not fetched]). Craft and Cairns, "Beyond Guidelines: What Can We Learn from the Visual Information Seeking Mantra?", IV 2005 pp. 110-118, argue the field lacks methodological guidance and examine the mantra as a frequently cited design guideline. [Verified abstract only] https://www-users.york.ac.uk/~pc530/pubs/craft_cairns.pdf . I did not read their detailed critique, so I do not summarise it.
- **Implication (inferred).** For disk analysis the mantra is incomplete: users must also *act* (remove, keep, reveal) and *track what they decided*. Add "decide" and "review decisions" stages after details-on-demand. Overview first still holds: show the whole-disk treemap/ranked list immediately, in progressive form while scanning.

---

## 5. Decision-making UX (hundreds of keep/remove decisions)

### 5.1 Photo-culling workflows as the closest analogue
- **Finding.** Culling tools centre on a fast binary pass: Pick/Reject flags (P / X) are quick, versus 1-5 stars for nuance; Photo Mechanic supports applying a star rating in one keypress and is described as built for speed; Narrative Select groups similar images into scenes for batch review; these tools are used as an isolated first pass before the editor. [Secondary: mostly a competitor's blog, treat with caution] https://imagen-ai.com/post/narrative-select-vs-photo-mechanic-vs-imagen/ , https://home.camerabits.com/wp-content/uploads/2021/05/Photo_Mechanic_prefs.pdf . I did not fetch Slidebox, FastRawViewer or Lightroom docs.
- **Implication (inferred).**
  - Model the review pass on culling: one item focused, one keystroke to flag (Keep / Remove / Later), automatic advance, never leave the keyboard. Three states, not two: "Later" prevents forced premature decisions.
  - Group similar items (same project, cache family, duplicates) so one decision covers a group, as Narrative Select groups scenes. This is the main lever against hundreds of serial decisions.
  - Flags are staging only. Nothing is deleted until a separate "apply" step, like Lightroom's reject-then-delete-rejected (my background knowledge of Lightroom; not verified here).

### 5.2 Decision fatigue: use cautiously
- **Finding.** Danziger et al. (PNAS 2011) reported favourable parole rulings falling from about 65% to near zero within a session and rebounding after breaks. Glöckner argued rational time-management by judges can produce the same pattern, so the result is contested. [Verified, search summaries] https://pmc.ncbi.nlm.nih.gov/articles/PMC3084045 . I did not retrieve ego-depletion replication results.
- **Implication.** Do not cite "hungry judges" as proof. The weaker, safe design principle is that long serial decision runs degrade consistency in practice (inferred). Mitigate by: batching by group, defaults that are correct for most items, showing progress and stakes ("reviewed 140 of 400, 38 GB flagged"), and making session breaks free (decisions auto-saved, resumable).

### 5.3 Undo versus confirm
- **Finding.** Experts argue that for reversible actions undo beats confirmation dialogs; Aza Raskin's "Never Use a Warning When You Mean Undo" is the usual source (not Jef Raskin, who is sometimes mis-credited). Nielsen Norman Group is reported as aligned. I found no controlled study comparing the two; the case rests on expert consensus. [Secondary] https://notes.andymatuschak.org/zXH4ASvHNz488hCNgrBjQJK , https://dev.to/137foundry/how-to-choose-between-confirmation-dialogs-undo-windows-and-soft-delete-patterns-1opj
- **Implication.**
  - Default removal = move to Trash (macOS Trash is the OS-level undo) with a session undo stack. No per-item confirm dialogs.
  - Reserve a confirmation for the truly irreversible step: emptying Trash, or deleting where Trash is unavailable (network volumes, external drives without a Trash). Phrase it with concrete totals, not "Are you sure?".
  - Show a summary of the batch (count, GB, categories) before applying, as an informative review step rather than a yes/no gate (inferred).

### 5.4 Loss aversion and defaults
- **Finding.** Johnson and Goldstein (Science 2003) found much higher organ-donor registration under opt-out than opt-in defaults; later work cautions the effect is not simply transferable and can crowd out related behaviour. [Secondary] https://thedecisionlab.com/insights/health/can-defaults-save-lives-the-power-of-default-options-on-life-saving-decisions . I did not retrieve loss-aversion coefficients or endowment-effect studies; I state none.
- **Implication (inferred).**
  - Defaults are powerful, so the default state of every item must be "Keep". Never pre-flag for deletion anything the user could regret (documents, photos, project folders).
  - Suggested pre-flags are acceptable only for regenerable things (caches, build artefacts, derived data), clearly labelled as regenerable and reversible.
  - Frame by regret avoidance: show "last opened", "can be regenerated", "also exists in iCloud/Time Machine" (if detectable), so loss aversion is addressed with information rather than with friction.

---

## 6. Keyboard-first, palettes, expertise

### 6.1 Novice-to-expert
- **Finding.** CommandMaps (Scarr, Cockburn, Gutwin, Bunt, CHI 2012): no significant speed difference for novices versus traditional menus, but experts were significantly faster than with menus and the Ribbon, because hierarchical organisation slows experts. Marking-menu field data: marks averaged 3.5x faster than menu selection, yet experts sometimes fall back to menus to refresh memory. ExposeHK (CHI 2013): showing hotkeys when a modifier is held substantially helps the transition from beginner to expert. Related surveys: Cockburn, Gutwin, Scarr, Malacria, ACM Computing Surveys 2014 (DOI 10.1145/2659796); Scarr et al., "Dips and ceilings", CHI 2011. [Secondary: abstracts] https://hci.cs.umanitoba.ca/publications/details/improving-command-selection-with-commandmaps , https://billbuxton.com/MMUserLearn.html , https://dumas.ccsd.cnrs.fr/CRISTAL-MJOLNIR/hal-01894253v1
- **Implication.**
  - Every command is reachable by mouse with visible affordances, by single-key shortcut, and by palette search. The same labels in all three so one transfers to the next.
  - Holding a modifier (for example Option) overlays shortcut hints on the visible controls (ExposeHK pattern).
  - Flatten command hierarchy where possible; novices lose nothing and experts gain speed (CommandMaps).

### 6.2 Superhuman, Linear, Raycast
- **Finding.** A blog guide states Superhuman's public threshold is 100 ms (internal 50-60 ms) and key-repeat tuned to 65 ms; another says Linear opens its command menu on one key. These are from secondary blogs with no primary citation. [Secondary, unverified] https://blakecrosley.com/de/guides/design/superhuman
- **Implication.** The 100 ms figure coincides with the Card "perceptual fusion" band (Section 3.1), so adopt it from Liu and Heer / Card, not from product folklore. Command palette (Cmd-K) with fuzzy search over *actions and locations* (files, directories, filters) is a safe pattern (inferred).

---

## 7. Motion and animated transitions

- **Finding.** Heer and Robertson (InfoVis 2007) extended data-graphics models with a transition taxonomy, proposed design principles (congruence, apprehension), and ran two controlled experiments concluding that "animated transitions can significantly improve graphical perception". Staged transitions, such as moving points to their x positions and updating the axis first, then morphing to bars, are illustrated against direct interpolation. The project page reports no error percentages or durations, and I did not obtain the full paper's duration or error values. [Verified abstract; numbers not found] https://idl.uw.edu/papers/animated-transitions
- **Implication (inferred).**
  - Preserve object identity: a rectangle that persists across zoom, reorder, or filter should *move*, not fade out and in. Treemap layout stability (Section 1.4) is what makes this possible.
  - Stage multi-change transitions (first remove, then re-layout neighbours, then rescale) rather than interpolating everything at once.
  - Durations: the 100 ms to 1 s time constants in Card's table (Section 3.1) bound feedback; I have no study-derived animation duration to cite. Reasonable starting point to tune by feel: about 150-250 ms for local changes, about 300-500 ms for view-to-view transitions (my numbers, unverified). Respect the macOS "Reduce Motion" setting.

---

## 8. Colour

- **Finding.** The Okabe-Ito palette has 8 colours (#E69F00, #56B4E9, #009E73, #F0E442, #0072B2, #D55E00, #CC79A7, #000000), designed for colour-universal design and popularised by Bang Wong (Nature Methods 2011). For more than 8 categories, one source suggests adding shape/pattern or using Paul Tol's palette (up to 12 colour-blind-safe). Viridis-family maps (viridis, plasma, inferno, magma, cividis) are listed as perceptually uniform, colour-blind-safe sequential maps. [Secondary] https://rdrr.io/cran/factoextra/man/factoextra_palette.html , https://conceptviz.app/blog/scientific-color-palette-for-research-papers-and-posters . Kong et al. [Verified]: luminance is perceptually separable from area judgement. I did not retrieve Ware's limit on distinguishable categorical colours or dark-UI legibility studies.
- **Implication.**
  - Cap categorical colour at about 8 file categories (Documents, Media, Code, Apps, System, Caches, Archives, Other) and use the 9th+ as neutral grey; never encode raw file extension by colour (hundreds of hues are unreadable). This cap is inferred from the 8-colour palette, not from a measured limit.
  - Sequential variables (age, count) use a perceptually uniform ramp such as a viridis-family map, which is also CVD-safe.
  - Dark UI: do not simply reuse the light palette; check contrast of labels on each cell colour programmatically (WCAG contrast thresholds are general knowledge, not fetched here) and verify with a CVD simulator (inferred).
  - Do not use colour alone for the keep/remove state: add icon or pattern so it survives CVD.

---

## Top 15 design rules (ranked by expected impact)

1. **Latency budget first.** Hover/brush/cross-view highlight <= 100 ms (target one frame); navigation <= 1 s; show progress for anything near 10 s. 500 ms of added delay measurably cut exploration, with carryover (Liu and Heer).
2. **Progressive, interactive scan.** Show the live treemap and ranked list while scanning; never block on completion (supports rule 1 and the carryover finding; progressive refinement per Falcon).
3. **Removal is Trash plus undo, never per-item confirm.** Confirmation only for irreversible steps, with concrete totals. (Expert consensus; no controlled study found.)
4. **Default to Keep.** Pre-flag only clearly regenerable items, labelled as such. Defaults are powerful (Johnson and Goldstein, with caveats).
5. **Culling-style review pass:** one item focused, single-key Keep / Remove / Later, auto-advance, flags staged until an explicit apply.
6. **Group decisions.** Batch by directory, cache family, duplicate set so hundreds of items become tens of decisions.
7. **Treemap as the primary decision surface; ranked bars beside it.** Treemaps win for directory-vs-file comparisons and above about 2-4k elements; bars win for a few hundred items (Kong et al.).
8. **Honest "small items" cells.** Aggregate sub-pixel items into a clickable, summed cell per parent; never drop them silently; expand on zoom (DOI-tree idea, inferred).
9. **Stable layout.** Deleting an item must move neighbours minimally; use stability-oriented layout and measure it (Hahn et al.; squarify trade-off).
10. **Avoid extreme aspect ratios, but do not chase squares.** Target moderate ratios (Kong et al.).
11. **Cumulative share-of-space view** (Lorenz/Pareto) for the long tail; avoid silent log axes. Label log decades in human units (lay-comprehension evidence is mixed but poor in some studies).
12. **Strong information scent on every cell and row:** size, last opened, regenerable flag, share of parent. Rank by gain per effort (Pirolli and Card).
13. **Same commands via mouse, shortcut and palette, with modifier-held hint overlay** (CommandMaps, ExposeHK).
14. **Animate with object constancy and staging;** respect Reduce Motion; keep durations short (Heer and Robertson; durations are my tuning).
15. **Colour discipline:** at most 8 categorical hues (Okabe-Ito family), uniform sequential ramp for age/count, non-colour redundancy for state, automated contrast check on dark UI.

---

## Where the research contradicts common practice in disk tools

Note: statements about what existing disk tools do come from general knowledge of the category (cushion-shaded treemaps coloured by file extension, radial sunburst browsers, confirm-then-delete dialogs). I did not fetch or test those products in this session.

1. **Sunburst-only overview.** Participants preferred sunburst (51 of 60) and it did better on first use, yet users found it frustrating for size comparison, and two-thirds said treemaps are better for that task (Stasko et al.). A tool whose job is comparing sizes should not rely on radial layout alone.
2. **Chasing squares.** Common practice (squarify) optimises toward squares. Kong et al. found comparing two squares degrades accuracy and that non-extreme non-unity ratios may beat squares.
3. **Per-item "Are you sure?" dialogs.** The expert consensus favours reversible actions with undo, which also avoids dialog fatigue across hundreds of decisions (consensus only, not controlled evidence).
4. **Colour by file extension.** Many tools do this. Categorical perception supports about 8 hues; hundreds of extensions cannot be distinguished or made CVD-safe. Group into categories.
5. **Relayout on every change.** Re-running a layout after each delete makes the map jump, defeating object constancy. Stability-aware layout is a documented research topic (Hahn et al.).
6. **Treemap for everything, or bars for everything.** The crossover is data-dependent (about 2048-4096 leaves in Kong's setup), so a single mandated view is wrong at one end of the distribution.
7. **Scan-then-show.** Blocking until the scan completes conflicts with the finding that delay changes exploration strategy and that early delay hurts later performance.
8. **Deleting from the visualisation with no review state.** Photo-culling tools separate flagging from applying; disk tools commonly delete directly (general knowledge, unverified).

---

## Gaps (not found or not fetched in this session)

- Full text of: Shneiderman 1992 treemaps; Bruls et al. 2000 (only a secondary snippet); van Wijk and van de Wetering 1999; Blanch and Lecolinet 2007; Card and Nation 2002; Heer and Card DOITree; Grosjean et al. SpaceTree; Crossfilter; Imme; Shneiderman 1996 mantra; Heer and Robertson full paper (no durations or error numbers obtained); Pirolli and Card 1999 (secondary only).
- No source found for: Lorenz/Pareto comprehension by laypeople; density plot/overplotting studies; Ware on categorical colour limits; dark-mode legibility; loss-aversion coefficient or endowment effect for digital deletion; any controlled undo-vs-confirm study; any study of deletion regret in file management; primary documentation for Superhuman/Linear/Raycast; Slidebox/FastRawViewer/Lightroom flags.
- Specific animation durations are not supported by anything I read. The 150-500 ms values above are tuning starting points, not literature.
- Kong et al.'s aspect-ratio symbols were garbled in PDF text extraction (shown as "9 2" and "3 2"). I interpret them as 9:2 and 3:2 (inferred); check the typeset paper before quoting.
