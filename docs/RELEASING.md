# Releasing

The `VERSION` value, `runtime.lock.json` bundle version, WASIX package version,
and Git tag are one invariant. For version `0.1.0-dev.2`, the only accepted tag
is `v0.1.0-dev.2`.

## Procedure

1. Change the compatibility lock, patches, or packaging as needed and increment
   all version fields together.
2. Let the pull-request workflow pass Linux amd64, macOS arm64, and Windows
   amd64.
3. Merge the reviewed commit to `main`.
4. Create an annotated tag on that exact main commit and push it:

   ```bash
   git switch main
   git pull --ff-only
   test "v$(<VERSION)" = "v0.1.0-dev.2"
   git tag -a "v$(<VERSION)" -m "Wurster Edge Runtime v$(<VERSION)"
   git push origin "v$(<VERSION)"
   ```

The tag workflow rebuilds and retests all three platforms. The `release` job
checks the tag/version match and waits for all final archives. It then creates
one GitHub Release with the three bundles and `SHA256SUMS`.

Workflow concurrency is keyed by PR number or commit SHA. A tag pushed for the
new main commit supersedes a redundant branch build of the same SHA, while
never sharing a concurrency group with an unrelated release.

## Failure behavior

If any platform fails, the release job is skipped and no GitHub Release is
created. Fix the source and increment the version; do not move or reuse a
published tag. If a tag failed before release publication, delete that failed
tag only after confirming that no release exists, then make a new versioned
commit and tag.
