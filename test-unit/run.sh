#!/bin/sh
# Build and run the Pipeline unit tests out-of-tree.
#
# This deliberately assembles a throwaway dune project in a temp directory and
# copies the sources into it, rather than committing a dune/dune-project here.
# That keeps these tests completely invisible to the mirage/docker build of the
# firewall (which globs the repo root), so they can never break the reproducible
# build or the qubes-firewall.sha256 check.
#
# Requires an opam switch with: lwt logs alcotest alcotest-lwt
#   opam install lwt logs alcotest alcotest-lwt
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp "$root/pipeline.ml" "$root/pipeline.mli" "$here/test_pipeline.ml" "$work/"

cat >"$work/dune-project" <<'EOF'
(lang dune 3.0)
EOF

cat >"$work/dune" <<'EOF'
(test
 (name test_pipeline)
 (libraries lwt lwt.unix logs alcotest alcotest-lwt))
EOF

cd "$work"
exec dune runtest --force
