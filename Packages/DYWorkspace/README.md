# DYWorkspace

The headless app model. Every view binds to one `Workspace` (`@MainActor @Observable`). No SwiftUI, no Metal. Depends on DYCore, DYScan, DYAnalysis, DYAdvisor, DYDecide, DYSQL and DYPreview (types only).

```swift
let workspace = Workspace(environment: .live(mover: SystemTrash()))   // the app entry point only
// or, for --demo and previews:
let workspace = Workspace(environment: .demo(dataDirectory: tempDirectory))
workspace.open(.demo)                  // or .path("/Users/me")
```

`Workspace` never names `SystemTrash`. The app passes the real mover to `WorkspaceEnvironment.live(mover:)`. A test enforces this.

## Rules of the model

- **The UI never blocks.** Rules, query, decisions and Trash changes recompute on a background task. An older run is cancelled, and only the newest result is published. Until it lands, views keep the previous `lens` and `isRecomputing` is true.
- **Hover and selection never recompute anything heavy.** `hover` is a plain property. Selection work is proportional to the selection, not the tree.
- **Selection is keyed by path.** It survives snapshots, rescans and kind refinement. `selectionCount` and `selectionBytes` are always current, and bytes are counted once when a folder and its contents are both selected. The scan root can be selected, and `RemovalPlanner` blocks it.
- **Marks apply to the selection, or to the current review item, only.** With neither, `mark(_:)` returns false and sets `notice`.
- **Unknown is nil, never zero.** See the ledger.
- **Apply is refused until the safety advice exists** (`canApply`), because the planner needs it to block `never` items.

## State to bind to

| Group | Properties |
|---|---|
| Source and scan | `source`, `tree`, `scanPhase` (`idle`, `loadingCache`, `scanning`, `finished`), `scanProgress`, `isLiveSnapshot`, `isShowingCachedScan`, `cachedScanAge` ("3 days ago"), `scanWasCancelled`, `volumes` |
| Lens | `lens` (rules + query + Trash), `baseLens` (no query), `isRecomputing`, `nodeStyle`, `ignoreResult`, `resolved` |
| View options | `lensKind`, `metric`, `colorMode`, `fieldClock`, `focus`, `breadcrumb`, `hover`, `queryText`, `query` (`query.errors` for malformed terms) |
| Selection | `selectionPaths`, `selectedNodes`, `selectionCount`, `selectionBytes`, `primarySelectionPath` |
| Analyses | `analysis[stage]` (`idle`, `running(fraction:)`, `done`, `cancelled`) for `reclaim`, `ownership`, `kinds`, `duplicates`; `reclaimReport`, `ownershipReport`, `kindRefinement`, `duplicateReport`, `worklists` |
| Lens results | `things` and `thingsThreshold`, `spectrum`, `field`. Only the active `lensKind` is computed. |
| Plan | `plan`, `planIsRefined`, `canApply`, `stagedBytes`, `planEstimateText`, `isApplying`, `applyProgress`, `lastExecution`, `canUndoApply`, `trashedPaths` |
| Review | `review`, `reviewPreview`, `reviewUpcoming(count:)` |
| Messages | `notice` (`message`, `canUndo`), `undoNotice()`, `dismissNotice()` |
| Ledger | `reconciliation` |
| SQL | `sqlText`, `sqlPhase` (`idle`, `running`, `finished`, `failed(SQLFailure)`), `sqlResult`, `sqlDrillRow`, `sqlIsFiltering`, `sqlFilterSummary` ("12 things · 184 GB", nil when not filtering), `sqlHistory` |

## Commands

- **Open**: `open(_:useCache:)`, `cancelScan()`. A path opens its cached scan at once (`isShowingCachedScan`), then rescans. While a cached scan is on screen, snapshots are ignored and the fresh tree replaces it when the scan finishes. Cancelling that rescan keeps the cached scan.
- **Views**: `setLens`, `setMetric`, `setColorMode`, `setFieldClock`, `setThingsItemTarget`, `setQuery`, `setFocus`, `zoomIn`, `zoomOut`.
- **Selection**: `click(_:additive:)` (a plain click on the only selected node clears it), `select(_:)`, `select(paths:)`, `addToSelection`, `clearSelection`, `isSelected`.
- **Marks**: `mark(.keep | .remove | .later | .none)`, `mark(_:nodes:)` (selects first, so the user sees what is marked), `undoDecision()`, `redoDecision()`.
- **Hide**: `hide(.path | .name | .ext, nodes:)` adds a rule and posts a notice with undo. `setRule(_:enabled:)`, `deleteRule(_:)`. The ledger still counts hidden bytes.
- **Analyses**: run automatically after a scan in this order: reclaim report, ownership, kind refinement (the tree is swapped for `tree.replacingKinds`, so node ids stay valid, and `.dataless` files are never read). `findDuplicates()` runs only on request, because it reads file contents. `cancelAnalyses()` stops all of them.
- **Review**: `startReview()` (async: the selection, or the largest undecided files under the focus), `startReview(nodes:title:)`, `startReview(family:)`, `startReview(worklist:)`, `reviewVerdict(_:)` (advances), `reviewGo(to:)`, `endReview()`. `undoDecision()` also steps the review back. `ReviewSession` exposes `current`, `index`, `isFinished`, `items` and `tally` (`kept`, `removed`, `later`, `left`, `removedBytes`, `decidedBytes`).
- **Plan**: `applyPlan()` (async, returns the `ExecutionReport`), `cancelApply()`, `undoApply()`. After Apply the moved paths leave the views (`reconciliation.removedThisSessionBytes`) and their marks are cleared. Undo puts them back and restores the marks.
- **SQL**: `runSQL(_:)` (background; a newer run cancels an older one; a failure leaves the previous filter in place), `cancelSQL()`, `clearSQL()` (views return to normal; text and history stay), `drillSQL(row:)` (`.groups` only; nil returns to every group), `selectSQLResults()`, `reviewSQLResults()`. See "SQL results" below.
- **Waiting**: `await settle()` returns when all background work is done. Use it in tests and the CLI.

## Plan wording

`plan.estimateIsLowerBound` is true when at least one figure is a floor. Say "frees at least" only then. `planEstimateText` does this for you ("frees at least 41.2 GB once the Trash is emptied"). The plan first appears with scan-time figures, then `planIsRefined` flips once the injected `ReclaimProbing` has measured each item.

## SQL results

A `.nodes` or `.groups` result is a set of things on disk, and every view shows it through the same path as the `/` query. A node in the set matches with its whole subtree, and the set is ANDed with the `/` query. `baseLens` ignores SQL, so the ledger still reconciles (`filteredBytes` covers the query and the set). `.tableOnly` results leave the views as they were and clear any earlier SQL filter.

- Runs only after the scan has finished. Before that, `sqlPhase` is `failed(.invalid("SQL is available when the scan finishes."))`.
- The query reads `baseLens`, the resolved decisions, the safety tiers and `now`, so `visible`, `mark` and `safety` match the app. If a lens is being recomputed, the run waits for it.
- A result stays true: after a tree swap, hide rule, decision, Trash or tier change the statement re-runs on the new lens, cancelling any older run. A set never applies to a tree its ids don't belong to; it is dropped until the re-run lands. Kind refinement keeps ids, so the result is rebound to the refined tree. `sqlDrillRow` survives a re-run only when the row count is unchanged.
- `sqlHistory`: newest first, at most 20, no duplicates, saved as `sql-history.json` under the data directory.
- SQL never marks anything, never builds a plan and never calls the Trash mover. Marks still go through selection and `mark(_:)`.
- `sqlFilterSummary` counts the nodes the result names, matching the results table. The bytes are the lens root: each byte once, even when a folder and its contents are both rows, and including the folders above the set.

## Ledger (`reconciliation`)

A `Reconciliation` value: `visibleBytes/Files`, `hiddenBytes/Files`, `hiddenByRule` (per rule, largest first), `filteredBytes/Files`, `removedThisSessionBytes`, `hardlinkBytesSaved`, `cloneBytesSaved`, `unreadableDirectories`, `limitedByPermissions`, `scannedBytes`, and a labelled remainder. `visible + hidden + filtered + removed == scannedBytes`.

`volumeTotal`, `volumeAvailable` and `remainderBytes` are nil unless the scan root is a mounted volume (or the demo supplies sample values, then `usesSampleValues` is true). `remainderBytes` is signed: negative means the scan holds more than the volume reports as used. Show `remainderLabel` beside it.

## Looking things up

- `summary(for:)` gives the HUD figures (`NodeSummary`: size, share of parent, modified, tier, rule title and consequence, decision). Cheap enough for every hover.
- `previewItem(for:)`, `previewItem(path:)`, `selectionPreview`, `reviewPreview` build `PreviewItem`s, with `largestChildren` for directories and `isDataless` set from the scan. Feed `reviewUpcoming()` to `PreviewController.prepare`.

## Environment and persistence

`WorkspaceEnvironment` injects: `homePath`, `dataDirectory`, `mover`, `appCatalog`, `reader`, `probe`, `clock`, `startScan`, `volumeForRoot`, `volumes`, plus the sample disk and sample ledger for demo mode. `defaultDataDirectory()` is `DEEPYELLOW_HOME` when set, else `~/Library/Application Support/DeepYellow`.

Under the data directory: `decisions.json`, `ignore-rules.json`, `trash-journal.json` (not in demo) and `scans/<name>.dyscan` (not in demo). Nothing is written anywhere else. `ScanCache.defaultURL` is deliberately not used, because it ignores `DEEPYELLOW_HOME`.

## Demo mode

`WorkspaceEnvironment.demo(dataDirectory:)` uses the `SyntheticTree` disk plus deterministic additions: duplicate files, leftover app folders, one extensionless file that kind refinement identifies, and a Docker image that frees less than it occupies. The mover is `DemoTrash`, in memory, recording every call in `calls` and never touching the disk. Any scan request returns the sample disk. The clock is fixed so ages are reproducible. The ledger shows explicit sample values.

`DemoTrash` answers `exists(path:)` from its own in-memory record, so a demo Apply then Undo round-trips without reading the real disk, on any machine.

## Tests

`swift test --package-path Packages/DYWorkspace`. Tests use temp data directories and never construct `SystemTrash`.
