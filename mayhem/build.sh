#!/usr/bin/env bash
#
# mayhem/build.sh — build radicle-link's parse_json cargo-fuzz target as a sanitized
# libFuzzer binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), plus the
# link-canonical known-answer test suite (normal flags) so mayhem/test.sh only RUNS it.
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem.
# The Rust toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo
# (pinned by the Dockerfile ENV — absolute, $HOME-independent).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - This FIRST build (in CI, online) populates the cargo registry under $CARGO_HOME.
#   - The PATCH re-run resolves crates from that cache. The rlenv runtime exports
#     CARGO_NET_OFFLINE=true for the re-run; we do NOT hard-code --offline here (it
#     would break this first, online build).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "${SRC:-/mayhem}"
SRC="${SRC:-/mayhem}"

: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=2 -Zdwarf-version=3 -Clinker=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh}"

: "${SANITIZER_FLAGS=-fsanitize=address,undefined}"
RUST_SAN=""
CARGO_FUZZ_SAN="none"
case "$SANITIZER_FLAGS" in
  *address*) RUST_SAN="-Zsanitizer=address"; CARGO_FUZZ_SAN="address" ;;
esac

export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing ${RUST_SAN} -Cforce-frame-pointers ${RUST_DEBUG_FLAGS}"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" --sanitizer "$CARGO_FUZZ_SAN" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "=== building link-canonical known-answer tests (normal flags) ==="
env -u RUSTFLAGS cargo test --manifest-path link-canonical/t/Cargo.toml --no-run

echo "build.sh complete"
