# Query language

There is one small language, and it is used everywhere. Press <kbd>/</kbd> to type a query. It filters every view live, and brushing in [Spectrum](views.md#spectrum) or [Field](views.md#field) writes into it, so the filter is always visible and editable.

```
size>100mb age>1y kind:video -path:Photos ext:mov,mp4 is:clone mark:remove safe:safe
```

A query is a list of terms separated by spaces, and a file must match **all** of them. Put a `-` in front of a term to negate it. Wrap text that contains spaces in double quotes, for example `path:"Application Support"`. At most 24 terms are used.

## Query or SQL

The query is the quick filter that works in every view as you type. For joins, grouping, sums and calculations we use [SQL](sql.md), where a result with an `id` column becomes the set every view shows. The two combine, and a node must match both.

## Terms

| Term | Matches |
|---|---|
| `size>100mb`, `size<1gb` | Size greater or less than a value |
| `age>1y`, `age<2w` | Time since last **modified** |
| `opened>6m`, `opened<3d` | Time since last **opened** (accessed) |
| `kind:video` | A kind. See below. Commas combine: `kind:video,audio` |
| `ext:mov,mp4` | File extension, with or without the dot |
| `name:backup` | The name contains the text |
| `path:Photos` | The name or any parent folder's name contains the text |
| `path:Library/Caches` | With a `/`, the full path contains the text |
| `is:dir` | Is a folder: matches every file inside a matching folder |
| `is:clone` | Shares its data with an APFS clone |
| `is:hardlink` | Is a hard link |
| `is:package` | Is a package such as an app or a library bundle |
| `is:dataless` | Is an iCloud placeholder that is not stored here |
| `mark:keep`, `mark:remove`, `mark:later`, `mark:none` | Your decision on it |
| `safe:safe`, `safe:rebuild`, `safe:review`, `safe:never` | Its safety tier |
| `anything` | A bare word matches a name or a path |

Matching is case-insensitive.

## Units

| Sizes | Durations |
|---|---|
| `b`, `kb`, `mb`, `gb`, `tb` (decimal, 1 kb = 1,000 bytes) | `s` seconds, `h` hours, `d` days, `w` weeks, `m` months (30 days), `y` years (365 days) |

A bare number for a size is bytes, and a bare number for an age is days. Decimals work, for example `size>1.5gb`.

## Kinds

| Name | Also accepted |
|---|---|
| `video` | `videos` |
| `image` | `images` |
| `audio` | |
| `document` | `documents`, `doc`, `docs` |
| `code` | `data` |
| `application` | `applications`, `app`, `apps`, `library`, `libraries` |
| `archive` | `archives`, `disk`, `disks` |
| `other` | |

Kinds come from the file extension and from macOS type information. For files that would otherwise be `other`, they come from a look at the first bytes of the file. See [Architecture](architecture.md#kinds-without-guessing).

## Examples

| Goal | Query |
|---|---|
| Large videos untouched for a year | `kind:video size>1gb age>1y` |
| Everything I marked for removal | `mark:remove` |
| Big things DeepYellow considers safe | `safe:safe size>100mb` |
| Disk images and installers in Downloads | `path:Downloads ext:dmg,pkg,iso` |
| Everything except Photos and Music | `-path:Photos -path:Music` |
| Large files I have not opened in half a year | `size>500mb opened>6m` |

## Mistakes

If a term cannot be understood, it is ignored and listed under the query bar, for example "unknown kind" or "bad size unit". The rest of the query still applies.
