# Pipe Transport — Backend + Library Decision (benchmarked)

**For:** `pipe-transport-tprd.md` §6
**Author:** thadanisahil2@gmail.com
**Date:** 2026-06-03

### Benchmark hosts (device specifications)

| | **Host A — Unix (UDS/TCP/FIFO)** | **Host B — Windows (named pipe)** |
|---|---|---|
| Machine | Dell Latitude 5420, **bare-metal** | **VMware Virtual Platform (VM)** |
| CPU | Intel Core i7-1185G7 (11th Gen), 4 cores / 8 threads @ 3.00 GHz | 2× AMD EPYC 7C13 64-Core (host); **16 vCPU** allocated to the VM |
| RAM | 30 GiB | 24 GB |
| OS / kernel | Ubuntu, Linux 6.17.0-29-generic, x86_64 | Windows Server 2022 Standard, Build 20348 |
| Go | `go1.26.3 linux/amd64` | `go1.26.4 windows/amd64` |
| GOMAXPROCS at bench | 8 (`-8` suffix) | 16 (`-16` suffix) |

> ⚠️ **Hosts A and B are DIFFERENT machines** (Intel bare-metal vs AMD-EPYC VM). The per-host
> distributions are each valid for their own hardware, but the **cross-OS ratio between them is
> confounded** by CPU/vendor/virtualization differences — it is NOT a clean OS A/B. A true cross-OS
> comparison requires the *same* hardware (dual-boot, identical-spec boxes, or equal VMs on one host).
> Each §5 OS-tier is gated only against benches on its own OS, where this confound does not apply.

---

## 1. Decision

| Axis | Choice | New dependency? |
|---|---|---|
| Unix (Linux/macOS) backend | stdlib `net` — Unix domain socket, `SOCK_STREAM` | **none** |
| Windows backend | `github.com/Microsoft/go-winio` v0.6.2 — named pipe (`\\.\pipe\…`) | **none — already an indirect dep in `go.mod`** |
| Linux IPC primitive | Unix domain socket (UDS), **not** FIFO/named-pipe(`mkfifo`) | n/a |
| Framing | SDK-owned length-prefix (reuse `transport/*` convention) | n/a |

**Why go-winio:** it is the only maintained Go library that wraps Windows named pipes as
`net.Conn` / `net.Listener` (IOCP-backed, non-blocking), giving byte-for-byte interface parity
with the stdlib UDS path on Unix. It is **MIT-licensed** and **already present transitively** in
`go.mod` (`github.com/Microsoft/go-winio v0.6.2 // indirect`, pulled by testcontainers/docker),
so promoting it to a direct dependency adds **zero** new modules to the graph. `PipeConfig`
exposes `SecurityDescriptor` (SDDL ACL), `MessageMode`, and `Input/OutputBufferSize` for tuning.

**Why UDS over FIFO on Linux:** UDS is bidirectional + connection-oriented (`Accept`/`Dial`),
carries peer credentials (`SO_PEERCRED`), and maps 1:1 to the Windows named-pipe connection model.
FIFO is unidirectional, has no connection/accept semantics, and no peer authentication — it would
force a divergent API per OS. Benchmark below confirms FIFO's only edge (marginally faster for
sub-1 KB messages) does not justify the API split.

---

## 2. Benchmark — measured (multi-sample, `-count=12` medians)

Round-trip = client writes payload → server echoes → client reads it back (request-reply).
One-way latency ≈ ½ round-trip. `-benchtime=1s -count=12 -benchmem`; values below are the **median of
12 samples** (single runs are unreliable — the first one-shot UDS-64 B run read 4,407 ns vs the 5,521 ns
count=12 median, a 25% optimistic error). Harness: `/tmp/pipebench` (UDS/TCP/FIFO echo over `net.Conn` /
`os.File`) on **Host A**; `/tmp/winpipebench` (go-winio `ListenPipe`/`DialPipe`, byte-mode, 64 KB buffers)
on **Host B**.

**Host A — Unix (Intel i7-1185G7, bare-metal, Linux 6.17, go1.26.3):**

| Transport | Payload | median ns/op (RT) | one-way | allocs/op |
|---|---|---|---|---|
| **UDS** | 64 B | 5,521 | 2.76 µs | **0** |
| **UDS** | 1 KB | 5,676 | 2.84 µs | **0** |
| **UDS** | 64 KB | 21,470 | 10.7 µs | **0** |
| **UDS** | 1 MB | 357,936 | 179 µs | 0 |
| TCP-loopback | 64 B | 14,619 | 7.31 µs | 0 |
| TCP-loopback | 1 KB | 14,529 | 7.26 µs | 0 |
| TCP-loopback | 64 KB | 41,686 | 20.8 µs | 0 |
| TCP-loopback | 1 MB | 495,427 | 248 µs | 0 |
| FIFO (named pipe) | 64 B | 3,624 | 1.81 µs | 0 |
| FIFO | 1 KB | 3,678 | 1.84 µs | 0 |
| FIFO | 64 KB | 20,494 | 10.2 µs | 0 |
| FIFO | 1 MB | 451,115 | 226 µs | 0 |

**Host B — Windows (2× EPYC 7C13, VMware VM, Server 2022, go1.26.4):**

| Transport | Payload | median ns/op (RT) | one-way | allocs/op | B/op |
|---|---|---|---|---|---|
| **Named pipe (go-winio)** | 64 B | 76,730 | 38.4 µs | **8** | 640 |
| **Named pipe** | 1 KB | 74,256 | 37.1 µs | 8 | 640 |
| **Named pipe** | 64 KB | 151,214 | 75.6 µs | 8 | 648 |
| **Named pipe** | 1 MB | 802,752 | 401 µs | 8 | 1,158 |

### Operation-surface matrix (count=12 medians, per symbol)

Round-trip latency hides per-symbol cost (it is a ping-pong). These one-directional `Send`/`Recv`
streams + a `Connect` dial cycle isolate each §7 symbol. ns/op = median of 12.

| Operation | Unix UDS (ns) | UDS alloc | Windows pipe (ns) | Win alloc |
|---|---|---|---|---|
| `Send` 64 B | 1,064 | 0 | 4,906 | 3 |
| `Send` 1 KB | 1,312 | 0 | 3,393 | 3 |
| `Send` 4 KB | 1,660 | 0 | 8,214 | 4 |
| `Send` 64 KB | 8,522 | 0 | 37,829 | 4 |
| `Recv` 64 B | 1,058 | 0 | 5,179 | 4 |
| `Recv` 1 KB | 1,255 | 0 | 3,383 | 4 |
| `Recv` 4 KB | 1,688 | 0 | 8,070 | 4 |
| `Recv` 64 KB | 8,532 | 0 | 39,476 | 4 |
| Round-trip 4 KB | 5,112 | 0 | 86,125 | 8 |
| **`Connect`** (dial+accept+close) | **10,393** | 19 | **10,026,044** | 23 |

**🔴 Dominant finding — Windows `Connect` ≈ 10 ms** (vs ~10 µs UDS, **~1000×**). Windows named-pipe
open (`CreateFile` + IOCP bind + instance handshake) is the cost; it is structural, not a hardware
artifact. **Design consequence:** on Windows the transport MUST reuse connections (pool or long-lived
`Conn`) — connect-per-message is a non-starter. Steady-state `Send`/`Recv` per symbol is cheap on both
OSes (Unix ~1.7 µs, Windows ~8 µs at 4 KB; allocs 0 vs 3–4). The earlier round-trip-only read
(74 µs "Windows latency", 8 allocs) over-counted: that was a Send+Recv ping-pong, not per-symbol cost.

## 3. Claims validated (Host A, count=12 medians)

| Claim (source) | Measured here (median) | Verdict |
|---|---|---|
| UDS small-msg latency ≈ 2.3 µs one-way ([yanxurui], [eli-bendersky]) | UDS 64 B = 5,521 ns RT → **~2.76 µs one-way** | ✅ confirmed (same order; this i7 runs slightly higher) |
| UDS ≈ 2.6× faster than TCP loopback for small messages | UDS 5,521 vs TCP 14,619 (64 B) → **2.65×** | ✅ confirmed |
| Named pipe / FIFO fastest for tiny messages ([baeldung]) | FIFO 3,624 < UDS 5,521 (64 B) | ✅ confirmed (FIFO −34%) |
| UDS beats pipes for large payloads ([baeldung] anon-pipe) | UDS 357,936 < FIFO 451,115 ns (1 MB) | ✅ confirmed |
| Transport adds no GC pressure | **0 allocs/op** all sizes (raw conn, Unix) | ✅ confirmed (Unix; Windows go-winio differs — below) |

## 4. Cross-OS analysis — read with the hardware-confound warning (top)

The two OS runs are on **different machines**, so the magnitudes below are not a clean OS A/B; they
do, however, expose two effects that are *structural to go-winio*, not hardware artifacts:

- **go-winio carries a fixed allocation floor**: ~**8 allocs/op + 640 B/op**, payload-independent at
  small sizes (64 B and 1 KB both 8/640). The stdlib UDS path allocates **0**. This is the IOCP
  wrapper, not framing — it would persist on any Windows hardware. So §5's `≤1 alloc/op` budget is a
  Unix-only target; Windows needs its own ≤10 alloc/op tier.
- **Small-frame latency is syscall-bound on both OSes**: 64 B ≈ 1 KB within each host (UDS 2.76 vs
  2.84 µs; pipe 38.4 vs 37.1 µs). Payload size only matters once you clear the per-op syscall cost.

What the cross-host numbers do **NOT** license: a statement like "Windows IPC is 13× slower than
Linux IPC." That ratio mixes Intel-bare-metal vs EPYC-VM. To make such a claim you must re-run **both
OSes on the same hardware** (dual-boot or equal VMs) — re-running on *different* devices does not fix
this; it just produces two correct-but-incomparable numbers.

go-winio fetch on Host B failed (corporate-network TLS handshake timeout to `proxy.golang.org`); the
dependency was **vendored** on a connected host and transferred, and the bench ran fully offline with
`-mod=vendor`.

## 5. Reproduce

```sh
# Host A (Unix):
cd /tmp/pipebench    && go test -bench=. -benchmem -benchtime=1s -count=12 -run=^$
# Host B (Windows), offline with vendored go-winio:
cd C:\Temp\winpipebench && go test -mod=vendor -bench=NamedPipe -benchmem -benchtime=1s -count=12 -run=^$
```

`bench_test.go` (UDS/TCP/FIFO echo round-trip) + `fifo_linux.go` (`syscall.Mkfifo`); Host B harness `winpipebench/bench_test.go` (go-winio round-trip) with vendored deps.

## 6. Sources

- go-winio API + IOCP + PipeConfig — https://github.com/microsoft/go-winio (MIT)
- IPC perf comparison — https://www.baeldung.com/linux/ipc-performance-comparison
- TCP/UDS/named-pipe bench — https://www.yanxurui.cc/posts/server/2023-11-28-benchmark-tcp-uds-namedpipe/
- UDS in Go — https://eli.thegreenplace.net/2019/unix-domain-sockets-in-go/
