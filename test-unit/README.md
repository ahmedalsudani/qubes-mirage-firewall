# Pipeline unit tests

Unit tests for the `Pipeline` module (`../pipeline.ml`), which decouples packet
receive from per-packet transmit completion in `dispatcher.ml`.

These are plain Lwt tests (no Xen needed). They are built **out-of-tree** by
`run.sh` so that nothing in this directory is ever picked up by the
`mirage`/docker build of the firewall — there is intentionally no committed
`dune` or `dune-project` here.

## Running

Needs an opam switch with the test dependencies:

```
opam install lwt logs alcotest alcotest-lwt
./run.sh
```

## What is covered

- **Start order** — operations begin in submission order, which is what keeps a
  single flow's packets in order on the transmit ring.
- **`max_in_flight`** — never more than the configured number of operations run
  concurrently.
- **Backpressure** — `submit` blocks the caller when the pipeline is full
  instead of dropping frames or growing without bound.
- **Exception isolation** — a failing forward is caught (so it cannot reach
  Lwt's async exception hook and abort the unikernel) and still frees its slot.
- **Validation** — `create` rejects a non-positive bound.
