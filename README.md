# rirdb

Daily merged Regional Internet Registry (RIR) allocation data with reproducible release artifacts and a semantic diff between consecutive builds.

The repository combines the extended delegated statistics published by:

- APNIC
- ARIN
- LACNIC
- AFRINIC
- RIPE NCC

A GitHub Actions workflow builds a new snapshot every day and publishes it as a GitHub Release.

## Daily build process

The workflow is defined in [`.github/workflows/daily-release.yml`](.github/workflows/daily-release.yml) and runs every day at:

```text
03:17 UTC
```

It can also be started manually with `workflow_dispatch`.

Each run performs the following steps.

### 1. Determine the release date

The workflow uses the current UTC date and creates a release tag in this form:

```text
rir-YYYY-MM-DD
```

Example:

```text
rir-2026-10-21
```

### 2. Capture the previous published build

Before generating the new snapshot, the workflow finds the dataset that should be used as the comparison baseline.

For a normal daily run, it selects the most recently published earlier `rir-*` release.

For a rerun on the same UTC day, if that day's release already exists, the workflow downloads the currently published dataset from that same release before rebuilding it. This means a same-day rerun produces a diff against the build it is about to replace.

The previous release asset used as input is:

```text
delegated-rir-extended.txt.gz
```

It is decompressed before comparison.

If there is no previous release, the build still succeeds and produces an empty diff marked with:

```text
previous=none
```

### 3. Download all five RIR datasets

[`scripts/merge-rir.sh`](scripts/merge-rir.sh) downloads the current extended delegated statistics from:

| Registry | Source |
| --- | --- |
| APNIC | `https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-extended-latest` |
| ARIN | `https://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest` |
| LACNIC | `https://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-extended-latest` |
| AFRINIC | `https://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-extended-latest` |
| RIPE NCC | `https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest` |

Downloads use retries, connection timeouts, and a maximum transfer time.

### 4. Validate each RIR input

Each downloaded file is checked before it can enter the merged dataset.

The validation requires records whose registry field matches the expected RIR and whose resource type is one of:

```text
ipv4
ipv6
asn
```

The build fails if a source does not contain a minimum expected number of valid delegated records. This prevents an empty response, error page, or obviously incomplete upstream file from being published as a valid snapshot.

### 5. Merge the delegated records

Only IPv4, IPv6, and ASN records are retained.

The merged file begins with:

```text
# registry|cc|type|start|value|date|status|opaque-id
```

Records then retain the delegated-statistics field layout, for example:

```text
ripencc|PL|ipv4|91.198.90.0|256|20100115|allocated|...
apnic|JP|ipv6|2001:200::|32|20020701|allocated|...
arin|US|asn|14618|1|20051104|allocated|...
```

The primary merged artifact is:

```text
delegated-rir-extended.txt
```

A deterministic gzip representation is also produced:

```text
delegated-rir-extended.txt.gz
```

The gzip output is created with metadata disabled so identical input produces identical compressed output.

### 6. Count resources in the snapshot

The build writes:

```text
counts.txt
```

with totals for each resource type:

```text
ipv4=<count>
ipv6=<count>
asn=<count>
```

### 7. Generate the consecutive-build diff

[`scripts/diff-rir.sh`](scripts/diff-rir.sh) compares the previous merged snapshot with the current one.

The comparison is set-based rather than line-position-based:

1. comment lines are removed;
2. records are sorted;
3. duplicate records are collapsed;
4. the two normalized sets are compared.

This prevents upstream record ordering from appearing as a data change.

The resulting file is:

```text
changes.txt
```

with a header such as:

```text
# previous=rir-2026-10-20
# current=rir-2026-10-21
# format=operation|registry|cc|type|start|value|date|status|opaque-id
```

Each changed record starts with an operation:

```text
-|ripencc|PL|ipv4|...
+|ripencc|PL|ipv4|...
```

where:

- `-` means the complete delegated record existed in the previous build but not in the current build;
- `+` means the complete delegated record exists in the current build but not in the previous build.

A modification to any field is represented as one removed record and one added record.

A compressed form is also published:

```text
changes.txt.gz
```

### 8. Count changes

The build generates:

```text
changes-counts.txt
```

with aggregate change counts:

```text
added=<count>
removed=<count>
added_ipv4=<count>
removed_ipv4=<count>
added_ipv6=<count>
removed_ipv6=<count>
added_asn=<count>
removed_asn=<count>
```

These counts are also included in the GitHub Release notes.

### 9. Generate checksums

`SHA256SUMS` is regenerated after all artifacts have been created.

It covers:

```text
delegated-rir-extended.txt
delegated-rir-extended.txt.gz
counts.txt
changes.txt
changes.txt.gz
changes-counts.txt
```

Consumers can therefore verify the integrity of every published data artifact.

### 10. Publish or update the GitHub Release

If the daily release does not yet exist, the workflow creates it.

If the release already exists, such as during a manual same-day rerun, the release notes are updated and all assets are uploaded with replacement enabled.

Each release therefore represents the latest successful build for that UTC date.

## Release artifacts

Every daily release contains:

| Artifact | Description |
| --- | --- |
| `delegated-rir-extended.txt` | Full merged APNIC, ARIN, LACNIC, AFRINIC, and RIPE NCC snapshot |
| `delegated-rir-extended.txt.gz` | Deterministic gzip-compressed snapshot |
| `counts.txt` | IPv4, IPv6, and ASN record counts |
| `changes.txt` | Semantic record diff against the preceding published build |
| `changes.txt.gz` | Compressed diff |
| `changes-counts.txt` | Added and removed record counts by resource type |
| `SHA256SUMS` | SHA-256 checksums for all published data artifacts |

## Running locally

Build a fresh merged snapshot:

```sh
bash scripts/merge-rir.sh dist
```

This produces the base snapshot artifacts under `dist/`.

To compare two locally available merged snapshots:

```sh
bash scripts/diff-rir.sh previous.txt current.txt dist previous-label current-label
```

For example:

```sh
bash scripts/diff-rir.sh \
  snapshots/rir-2026-10-20.txt \
  dist/delegated-rir-extended.txt \
  dist \
  rir-2026-10-20 \
  rir-2026-10-21
```

## Diff semantics

The diff describes changes to complete delegated-statistics records, not inferred business events.

For example, if an IPv4 allocation changes status, country code, date, size, or another field, the old full record is emitted with `-` and the new full record with `+`.

The diff therefore answers:

> Which delegated records disappeared, and which delegated records appeared, between two consecutive published builds?

It does not attempt to infer why a registry changed a record.

## Data interpretation

The merged database reflects delegated statistics published by the five RIRs. It should be treated as registry/allocation data rather than as an IP geolocation database.

In particular, the country-code field is part of the delegated registry data and should not be assumed to represent the current physical location of every address in the corresponding resource.

## Failure behavior

The workflow is intentionally fail-closed for source acquisition and validation.

A daily release is not published if:

- a required RIR source cannot be downloaded;
- a download is empty or obviously incomplete;
- a source fails the delegated-record validation;
- merge or diff generation fails;
- GitHub Release publication fails.

The previously published release remains available if a later run fails.
