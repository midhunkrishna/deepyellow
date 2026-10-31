# DeepYellow documentation

DeepYellow is a native macOS disk analyzer. It shows where your space went, tells you what each thing is and what removing it would cost, and moves only what you choose to the Trash. These pages are the full manual.

## Start here

| Page | What it covers |
|---|---|
| [Getting started](getting-started.md) | Install, grant access, scan, find your first gold, apply a plan |
| [Install](install.md) | Download, one-line installer, building yourself, and what to do **if macOS blocks it** |
| [FAQ](faq.md) | Short answers: is it safe, does it use AI, what about iCloud, why are the numbers different from Finder |

## Using it

| Page | What it covers |
|---|---|
| [Views](views.md) | Map, Things, Spectrum, Field, Rings, Browse, Reclaim, Review, colour modes, keyboard |
| [Query language](query-language.md) | `size>100mb age>1y kind:video` and every other term |
| [Safety and accounting](safety-and-accounting.md) | Tiers, staged decisions, the Plan, Trash and undo, the Ledger, Full Disk Access |
| [Reclaim rules](reclaim-rules.md) | Every built-in rule: pattern, tier, consequence, side condition, command |
| [Command line](cli.md) | `deepyellow things`, `reclaim`, `spectrum`, `dupes`; read-only by design |

## Building and maintaining

| Page | What it covers |
|---|---|
| [Building from source](building-from-source.md) | `make app`, tests, the packages |
| [Architecture](architecture.md) | Modules, the file tree, how Things, Reclaim and the Plan work |
| [Uninstall](uninstall.md) | Every path DeepYellow uses, and how to remove each |

## The short version

- **Gold means reclaimable.** Deep yellow is used for one meaning: space you could get back.
- **Nothing is removed without a Plan.** Apply only ever moves items to the Trash, and one step undoes it.
- **No network code, no telemetry, no AI.** Advice comes from a rule table and measured facts. You decide.
- **Open source, MIT.** Source: [github.com/midhunkrishna/deepyellow](https://github.com/midhunkrishna/deepyellow).
