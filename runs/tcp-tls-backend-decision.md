# TCP networking-library backend decision — `motadatagosdk/transport/tcptls`

**Date:** 2026-06-02 · **Status:** DECIDED · **Decision:** ship **stdlib `net` + `crypto/tls`** as the default backend.

## Question

Which TCP networking library sits behind the transport's swappable port — analogous to adopting **fasthttp** over `net/http` for the HTTP server. Candidate fasthttp-analogue for TCP+TLS: an event-loop / zero-copy library. After research, the only high-perf TCP lib with **native TLS** is **nbio** (gnet & netpoll list TLS as roadmap-only). So the POC is a 2-way: **stdlib** vs **nbio**, both pure-Go.

## Method (fair, reproducible)

Throwaway sibling module `motadata-go-sdk/src/tlsbench/` (untracked; `replace motadatagosdk => ../motadatagosdk`). One shared length-prefix framer, one cert-fixture set (ECDSA-P256 + RSA-2048), one harness above a common `spec.Backend` boundary, so deltas are attributable to the library. Admission gate (byte-exact echo incl. `MaxFrameSize` boundary + oversize rejection, mTLS rejection of an untrusted client cert, goleak) **passed by both backends before any timing**. Runs pinned `taskset -c 0-3`, `GOMAXPROCS=4`, `-count=8`, benchstat. Loopback, TLS 1.3, AES-128-GCM, single host (`11th Gen i7-1185G7`, 8 cores).

Two nbio modes measured, because nbio has two:
- **nbio_blocking** — `llib` TLS in blocking mode over a `net.Conn`. This is the only mode our **blocking** `Conn.Send/Recv` port can expose. Apples-to-apples vs stdlib (both goroutine-per-conn).
- **nbio_callback** — nbio's event-loop engine (`OnData` handlers). The conn-scale *ceiling*; **our blocking port cannot expose it**. Measured in W5 only.

## Results (benchstat medians)

### W1 — full handshake (sec/op; lower better)
| | stdlib | nbio_blocking |
|---|---|---|
| ECDSA-P256 | 1.065 ms | 1.029 ms |
| RSA-2048 | 2.378 ms | 2.064 ms |
| B/op | 127 KiB | 77 KiB |
| allocs/op | ~960 | ~1080 |

Near-parity, crypto-bound. nbio marginally faster + leaner bytes, slightly more allocs. **Not decisive.**

### W3 — small-frame round-trip latency (sec/op; lower better)
| frame | stdlib | nbio_blocking |
|---|---|---|
| 64 B | **14.86 µs** | 16.92 µs |
| 256 B | **15.70 µs** | 16.68 µs |
| allocs/op | **6** | 12 |

**stdlib wins** latency + half the allocs.

### W4 — throughput, round-trip (sec/op; lower better; naive framer)
| frame | stdlib | nbio_blocking | stdlib advantage |
|---|---|---|---|
| 1 KiB | 32.8 µs | 42.0 µs | 1.3× |
| 16 KiB | 59.9 µs | 108.5 µs | 1.8× |
| 64 KiB | 164.6 µs | 323.6 µs | 2.0× |
| 256 KiB | 531 µs | 1.088 ms | 2.0× |
| 1 MiB | 1.973 ms | 4.397 ms | 2.2× |
| B/op (1 MiB) | 2.02 MiB | 6.53 MiB | 3.2× leaner |

**stdlib wins decisively (~2×)** and allocates ~3× less. nbio_blocking 1 MiB also showed a ±527% variance stall (a multi-hundred-ms outlier) — its blocking path is unstable; `llib` is tuned for nbio's non-blocking feed, not blocking I/O.

**Impl-effect control** (naive vs pooled framing on stdlib): second-order (≤20% either way, size-dependent) — the backend dominates, not our framing.

### W5 — conn-scale footprint (the only place nbio could win)
| server | goroutines/conn | RSS/conn @10k |
|---|---|---|
| stdlib (goroutine-per-conn) | **1.000** | ~34 KiB |
| nbio_callback (event-loop) | **0.000** (O(cores) total) | ~22.5 KiB (~33% less) |

nbio's event-loop genuinely wins footprint: at 100k conns that is ~8 vs ~100k goroutines. **But this win exists only in callback mode, which the blocking port cannot expose.** (The 1k RSS figure for nbio was negative — same-process cross-subtest GC noise; the goroutine count is the exact metric and the 10k RSS is directional.)

## Decision

**Default backend = stdlib `net` + `crypto/tls`.** Rationale, against the pre-registered decision rule:
1. In the **only mode our blocking port can expose** (nbio_blocking), stdlib beats nbio on throughput (~2×) and latency, ties on handshake, and is leaner + more stable. nbio behind the current port is a **net loss**.
2. nbio's real advantage (conn-scale footprint) requires **callback mode**, which the blocking `Send/Recv` port cannot expose.
3. stdlib adds **zero dependency**; nbio adds a dep + a maintained `llib` crypto/tls fork to track. Both pure-Go (portability ties).

→ Adopt **stdlib** as the shipped default. Do **not** adopt nbio behind the blocking port.

## Follow-up (recorded, not blocking)

nbio's footprint win is real and matters for **many-long-lived-connection** deployments (e.g. a collector holding 100k agent conns). To capture it, the SDK would need a **handler/streaming port variant** (`OnMessage`-style callback API) in addition to the blocking `Conn.Send/Recv` port — then an nbio callback backend could be offered as an **optional adapter**. Filed as a TPRD §14 follow-up (non-blocking). The swappable-backend design (`Config.Backend` + `Config.BackendFactory`, TPRD §7) means this can ship later as an SDK update with **no consumer code change** — exactly the swap guarantee.

## Limitations
- Loopback, single host → absolute MB/s is an upper bound; decision rests on host-independent ratios + goroutine counts + allocs, all with large effect sizes (≥2×) relative to noise.
- W5 RSS measured in one process (client+server) → cross-subtest GC noise; goroutine-per-conn (exact) is the clean signal.
- W2 session-resumption not measured (the POC adapter builds a per-dial TLS config; persistent session cache would need a stateful backend). Resumption is TLS-engine-bound and ≈equal across both; not decision-relevant.
- nbio_blocking large-frame variance noted; would need investigation before any nbio adoption.

## Reproduce
```
cd motadata-go-sdk/src/tlsbench
go test ./bench/ -run 'TestAdmissionGate|TestNoGoroutineLeak' -v      # gate
ulimit -n 65536
taskset -c 0-3 env GOMAXPROCS=4 go test ./bench/ -run '^$' \
  -bench 'BenchmarkW1Handshake|BenchmarkW3RTT|BenchmarkW4Throughput' -benchmem -count=8 -benchtime=150ms
taskset -c 0-3 env GOMAXPROCS=4 go test ./bench/ -run TestW5Footprint -v   # footprint
```
Raw: `src/tlsbench/results/bench-raw.txt`, `benchstat.txt`, `footprint.txt`.

---

## Addendum — non-blocking high-perf at scale (concurrency sweep)

A follow-up directly tested the reframed goal **"non-blocking high-perf TCP+TLS at scale"**: nbio's native **event-loop callback** mode (its real strength) vs stdlib goroutine-per-conn, under a **concurrency sweep** of N active TLS-1.3 connections each looping send/recv (256 B frames, 2 s). This closes the gap left by the first POC (which benched throughput at N=1 only). TLS is asserted active per run (`State().Version == TLS 1.3`). `results/loadscale-final.txt`.

| N | ops/s (stdlib / nbio) | p50 (std / nbio) | p99 (std / nbio) | CPU/Mop s (std / nbio) | goroutines (std / nbio) | RSS MB (std / nbio) |
|---|---|---|---|---|---|---|
| 64 | **80442** / 46801 | **679µs** / 933µs | **3.1ms** / 6.5ms | **68.7** / 97.8 | 131 / 73 | 16 / 28 |
| 512 | **77794** / 47949 | **6.0ms** / 9.1ms | **16.3ms** / 58.2ms | **73.7** / 100.7 | 1027 / 521 | 41 / 47 |
| 4096 | **63831** / 46082 | **53.8ms** / 73.9ms | **63.0ms** / 172.9ms | **84.2** / 111.4 | 8195 / 4105 | 216 / 223 |
| 8192 | **63371** / 44674 | **115.8ms** / 194.1ms | **123.0ms** / 326.6ms | **89.4** / 112.5 | 16387 / 8201 | 349 / 410 |
| 16384 | **47017** / 37451 | **318.6ms** / 413.6ms | **331.4ms** / 758.4ms | **98.4** / 122.4 | 32771 / 16393 | 599 / 777 |

**stdlib wins throughput, p50, p99, and CPU/op at every concurrency level (1.3–1.7× throughput, up to 2.3× better p99 tail).** nbio's only advantage is goroutine count (~half) — which converts to **no** performance win, and comes with worse tail latency, ~30% higher CPU/op, worse RSS at 16k, and **handshake fragility under connect bursts** (nbio errored `tls: unexpected message` at 8k until its `WrapData` buffer was raised to 16 KiB and dials were throttled+retried).

**Why stdlib wins the non-blocking goal (the key finding):** Go's **runtime netpoller is already a non-blocking epoll/kqueue event loop**. stdlib `net` is *not* "blocking" — each goroutine parks on the netpoller and the runtime multiplexes; you get non-blocking I/O + a mature work-stealing scheduler + `crypto/tls`'s optimized code path. nbio reimplements an event loop **in userspace on top of the same epoll**, adding a callback-dispatch layer + its own buffer management + the `llib` crypto/tls fork — overhead that does not pay off until raw goroutine *count* (≈few-KB stacks) becomes the hard limit, which is far beyond 16k and even then trades against worse per-op efficiency. nbio's genuine niche (millions of mostly-**idle** connections, e.g. websocket push) is real but narrow; for **throughput/latency-bound** TLS transport it loses.

**Revised decision (unchanged winner, stronger basis):** **stdlib `net` + `crypto/tls` is the default for the non-blocking high-perf goal too.** The blocking `Conn.Send/Recv` port is not a liability — backed by the netpoller it *is* the high-performance non-blocking model, and goroutine-per-conn outperformed the explicit event loop at every tested scale. This **resolves OQ-006**: a handler/streaming port + nbio callback backend is **not** warranted on performance grounds (it lost). Revisit only if a future workload is millions of idle conns where goroutine-stack memory is the binding constraint.

Caveats: same-process client+server (RSS/goroutine totals include the identical client load on both arms; cross-arm deltas isolate the server model). nbio echo handler allocates per message (`append` copy) — buffer pooling could narrow its CPU/RSS gap, but not the ~1.4× throughput + 2× tail gap. Loopback; absolute ms are upper bounds, ratios are the signal.

Load sweep: `results/loadscale-final.txt`. Reproduce: `ulimit -n 200000; taskset -c 0-5 env GOMAXPROCS=6 go test ./bench/ -run TestLoadScale -v -timeout 900s`.
