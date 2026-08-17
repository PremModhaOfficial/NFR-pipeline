---
title: "Add TCP-over-TLS Transport to motadata-go-sdk"
author: "thadanisahil2@gmail.com"
date: "2026-06-02"
---

§Target-Language: go
§Target-Tier: T1
§Required-Packages:
  - "shared-core@>=1.0.0"
  - "go@>=1.0.0"

# Technical Product Requirements Document — TCP-over-TLS Transport (`transport/tcptls`)

## §1 Request Type

**Mode A (greenfield new package).** Adds a new package `motadatagosdk/transport/tcptls` providing a secure TCP transport with TLS 1.2+ for both client (dial) and server (listen) roles. No existing exported symbol is modified or removed. Agrees with §12 (new exports only → MINOR bump).

## §2 Scope

### In-Scope
- A neutral, swappable TLS-over-TCP transport exposing **stable port interfaces** (`Conn`, `Client`, `Listener`) plus a `Config`/`ServerConfig` + constructor (`Dial`, `Listen`) entrypoint, per the SDK `Config struct + constructor` convention.
- **Backend-swap mechanism** (hexagonal ports-and-adapters): the public surface references no `crypto/tls` / `crypto/x509` type. The default adapter (std `net` + `crypto/tls`) is compiled-in and selected at call time; an optional `Config.BackendFactory` dependency-injection hook admits alternative implementations **without** a global registry or `init()`. Swapping the underlying transport library is therefore an SDK-internal change that requires **zero consumer code change**.
- Neutral `TLSConfig` (enum `TLSVersion`/`CipherSuite`, cert/key/CA file paths, SNI `ServerName`, `ClientAuth` for mTLS, `SkipVerify` dev escape) mapped to the active backend internally.
- **Framed message I/O**: length-prefixed `Send([]byte)` / `Recv() []byte` with a `MaxFrameSize` memory-exhaustion guard. SDK owns framing.
- **Two consumption models over one backend**: a **blocking pull port** (`Conn.Send`/`Recv`) and an **async push port** (`Handler` with `OnConn`/`OnData`/`OnClose`, à la nbio). Both sit above the *same* swappable backend. On the default stdlib backend the push port is a thin goroutine-per-conn facade over the netpoller (so a handler MAY block without stalling other conns); a future event-loop backend can dispatch the same `Handler` callbacks natively (O(cores) goroutines) via the optional `HandlerBackend` capability — **with no consumer code change**. The async API is therefore an *ergonomics + swap-readiness* feature, not a perf claim (§6 benchmark: stdlib wins active traffic regardless of API shape).
- Client roles: dial with per-attempt timeout, optional connection pooling (reusing `core/pool/resourcepool`), optional dial retry with backoff+jitter, optional circuit breaker on dial (reusing `core/circuitbreaker`).
- Server roles: `Listen`/`Accept`, server certificate, SNI, optional mTLS client-cert verification.
- Optional `CredentialProvider` interface for certificate hot-reload / rotation (no process restart).
- TLS 1.2 minimum with secure cipher-suite defaults; TLS 1.3 negotiated when the peer supports it.
- Neutral `ConnectionState` (negotiated version, cipher, peer-cert chain) exposed without leaking stdlib types.
- OTel spans + metrics via the SDK `motadatagosdk/otel` facade; never raw upstream OTel.
- Sentinel errors matched with `errors.Is`, re-exported at package root.

### Non-Goals
- **No application-layer protocol** (no RPC, no request/reply semantics, no service mesh). This is a transport, not a protocol stack.
- **No QUIC / HTTP/3 / UDP / datagram** transport — covered by separate `transport/*` packages; this package is connection-oriented TLS-over-TCP only.
- **No multi-tenancy logic** — tenant context is caller-supplied; the SDK never sets `tenant_id` (per SDK-wide rule and G38).
- **No PKI / certificate-authority issuance, CSR signing, or ACME** — the package consumes certificates; it does not mint them.
- **No NATS coupling** — this transport is independent of `events/`; `nats_surface = no`.
- **No consumer-visible `crypto/tls` or `crypto/x509` types** on the public API — that coupling would defeat the swap guarantee and is explicitly out of scope.
- **No serialization / codec layer** — the transport is bytes-only (`Send([]byte)`/`Recv() []byte`). Callers compose any codec (`core/codec`, msgpack, JSON) at the call site, e.g. `conn.Send(ctx, codec.Pack(v))`. Keeping codec out of the port preserves byte-level swap purity and confines the codec wire-contract (a payload-encoding agreement both peers must share) to the caller, not the SDK. Transport-backend swaps remain wire-invisible.

## §3 Motivation

Services built on `motadata-go-sdk` increasingly need a direct, secure point-to-point byte transport that is **not** mediated by NATS — agent↔collector links, sidecar control channels, and bulk telemetry shipping where a broker hop is unwanted overhead. Today each consumer hand-rolls `net.Dial` + `crypto/tls`, duplicating handshake, framing, pooling, retry, and observability wiring, and pinning every consumer to the stdlib TLS implementation. Centralizing this in the SDK behind a stable port lets the platform team evolve the underlying transport (tuned TLS stack, alternative cipher backend, kernel-offload experiments) by shipping an SDK update alone — consumers in production upgrade the dependency and inherit the improvement without touching their code. The swap guarantee is the primary business driver: **update the SDK, not the fleet.**

## §4 Functional Requirements

| ID | Description | Priority | §7 Symbol |
|---|---|---|---|
| FR-TCPTLS-01 | `Dial` establishes a TLS 1.2+ connection to `Config.Address` and returns a ready framed `Conn`. | Must | `Dial`, `Client.Connect` |
| FR-TCPTLS-02 | `Listen` binds `ServerConfig.Address` and `Accept` returns inbound connections post-handshake; enforces mTLS client-cert verification when `ClientAuth` is set. | Must | `Listen`, `Listener.Accept` |
| FR-TCPTLS-03 | The public API exposes **no** `crypto/tls` or `crypto/x509` type; `TLSConfig` is a neutral struct mapped to the backend internally. | Must | `TLSConfig`, `TLSVersion`, `CipherSuite` |
| FR-TCPTLS-04 | `Send`/`Recv` use length-prefixed framing; `Recv` rejects frames larger than `Config.MaxFrameSize` with `ErrFrameTooLarge`. | Must | `Conn.Send`, `Conn.Recv` |
| FR-TCPTLS-05 | All I/O methods take `context.Context` first and honor deadline + cancellation. | Must | `Conn.Send`, `Conn.Recv`, `Client.Connect`, `Listener.Accept` |
| FR-TCPTLS-06 | Backend is selected via `Config.Backend` (default compiled-in `"std"`) or injected via `Config.BackendFactory`; no global registry, no `init()`. | Must | `Backend`, `BackendFactory`, `Config.Backend` |
| FR-TCPTLS-07 | Client-side connection pooling (reusing `core/pool/resourcepool`) is enabled by a non-zero `PoolConfig`; zero value disables pooling (default off). `DefaultPoolConfig()` gives one-line opt-in. | Should | `PoolConfig`, `DefaultPoolConfig`, `Client.Stats` |
| FR-TCPTLS-08 | Dial retry with exponential backoff + jitter when `RetryConfig` is set; retryable vs non-retryable classes are defined. | Should | `RetryConfig` |
| FR-TCPTLS-09 | Optional circuit breaker on dial (reusing `core/circuitbreaker`) opens after a failure threshold and short-circuits with `ErrCircuitOpen`. | Should | `BreakerConfig` |
| FR-TCPTLS-10 | `CredentialProvider` supplies certificates/roots at handshake time, enabling hot rotation without reconnect of existing conns. | Should | `CredentialProvider` |
| FR-TCPTLS-11 | `ConnectionState` exposes negotiated TLS version, cipher suite, and peer certificate subjects as neutral types. | Must | `Conn.ConnectionState`, `ConnectionState` |
| FR-TCPTLS-12 | All failure modes surface as sentinel errors matchable with `errors.Is`, re-exported at package root. | Must | `ErrHandshakeFailed`, `ErrFrameTooLarge`, … |
| FR-TCPTLS-13 | Dial, handshake, and accept emit OTel spans; frame/byte/connection counters + duration histograms emit via the `motadatagosdk/otel` facade. | Must | (observability, see §8) |
| FR-TCPTLS-14 | `Close` on `Conn`/`Client`/`Listener` drains gracefully within a context deadline and is idempotent. | Must | `Conn.Close`, `Client.Close`, `Listener.Close` |
| FR-TCPTLS-15 | `SkipVerify` is honored only with a logged WARN; secure cipher defaults apply when `CipherSuites` is empty; invalid TLS config fails fast with `ErrTLSConfigInvalid`. | Must | `TLSConfig`, `ErrTLSConfigInvalid` |
| FR-TCPTLS-16 | ALPN protocol IDs are advertised (client) / selected (server) when `ALPNProtocols` is non-empty; the negotiated value is reported in `ConnectionState.NegotiatedProto`; no mutually-acceptable protocol fails the handshake with `ErrALPNMismatch`. Empty `ALPNProtocols` disables ALPN. | Should | `Config.ALPNProtocols`, `ServerConfig.ALPNProtocols`, `ErrALPNMismatch` |
| FR-TCPTLS-17 | When `ServerConfig.AcceptShards > 1` on Linux, the server opens that many `SO_REUSEPORT` listeners on one address with parallel accept loops; off-Linux it falls back to a single acceptor. | Should | `ServerConfig.AcceptShards` |
| FR-TCPTLS-18 | The hot path (`Send`/`Recv`) uses pooled buffers and meets the §5 allocation budget (≤2 allocs/op) — no per-frame header/buffer allocation under steady state. | Must | `Conn.Send`, `Conn.Recv` (impl/NFR) |
| FR-TCPTLS-19 | `TLSConfig.SessionResumption` enables TLS 1.3 PSK / 1.2 ticket resumption (client LRU session cache + server tickets); resumed handshakes are reported via `ConnectionState` (a future `Resumed` field) and skip full-handshake CPU. | Should | `TLSConfig.SessionResumption` |
| FR-TCPTLS-20 | An async **push** consumption port: `Handler` (`OnConn`/`OnData`/`OnClose`) dispatched per accepted/dialed connection. `Listener.Serve` runs the server accept+dispatch loop; `ServeConn` drives one `Conn`. `OnData` frames are pooled (valid only for the call; copy to retain). The default stdlib backend implements this as a goroutine-per-conn facade — a handler may block without stalling other connections. | Should | `Handler`, `HandlerFunc`, `Listener.Serve`, `ServeConn` |
| FR-TCPTLS-21 | The async port is backend-swappable: a `Backend` MAY implement the optional `HandlerBackend` capability to dispatch `Handler` callbacks natively (event-loop). When absent, the package drives `Handler` via the blocking raw port with identical observable behavior. Swapping a `HandlerBackend` (e.g. nbio) in via SDK update requires **zero `Handler`-consumer code change**. | Should | `HandlerBackend` |

<!-- Each FR-id is referenced from §Skills-Manifest "Why required" and from generated code via [traces-to: TPRD-§4-FR-<id>]. -->

## §5 Non-Functional Requirements

### Performance Targets
Measured on loopback (client↔server in one process), 4 KiB frames, established connection unless noted. Numeric starting points; the perf architect refines at D1 into `design/perf-budget.md`.

- **Latency — `Conn.Send`** (per §7 symbol): p50 ≤ 25 µs, p95 ≤ 60 µs, p99 ≤ 120 µs.
- **Latency — `Conn.Recv`**: p50 ≤ 30 µs, p95 ≤ 70 µs, p99 ≤ 140 µs.
- **Latency — `Client.Connect`** (full TLS 1.3 handshake, loopback): p50 ≤ 1.5 ms, p95 ≤ 4 ms, p99 ≤ 8 ms. (Pooled reuse path: p50 ≤ 5 µs.)
- **Throughput**: ≥ 150,000 frames/sec on a single connection (4 KiB frames).
- **Allocation budget** (G104 enforced at M3.5): `Conn.Send` ≤ 2 allocs/op; `Conn.Recv` ≤ 3 allocs/op; pooled `Client.Connect` ≤ 1 alloc/op.
- **Complexity** (G107 scaling sweep at T5): `Send`/`Recv` O(n) in payload bytes; `Client.Connect` (pooled) O(1) amortized; `Listener.Accept` O(1).
- **Oracle margin** (G108): `Send`/`Recv` p50 ≤ 1.3× a raw `crypto/tls` + `bufio` reference implementation.
- **MMD (soak)** (G105): minimum 30 min soak for connection-leak and latency-drift symbols (`Connect`/`Close` churn, long-lived `Send`/`Recv`).

### Drift Signals
- Rising p99 `Send`/`Recv` latency at fixed throughput → buffer/GC pressure regression.
- Growing `connections.active` gauge under steady offered load → connection or goroutine leak.
- Falling pooled-`Connect` hit ratio → pool sizing/eviction regression.
- Rising `handshake.duration` p95 → TLS config / cert-chain validation regression.

Consumed by the perf architect at D1 to author `design/perf-budget.md`.

## §Perf-Engineering — Non-Blocking Model + Cloud Efficiency

### How we provide non-blocking TCP
The transport's I/O is non-blocking by virtue of **Go's runtime netpoller** — NOT a userspace event loop. Every goroutine that calls `Read`/`Write` parks on **epoll/kqueue**; the runtime multiplexes thousands of connections over a few OS threads and resumes goroutines via work-stealing. This *is* non-blocking I/O. A benchmark (concurrency sweep, N = 64…16384 active TLS-1.3 conns) showed this model beats an explicit userspace event loop (nbio) on throughput (1.3–1.7×), p50, p99 (up to 2.3×), and CPU/op at every scale — because nbio re-implements a reactor on top of the *same* epoll, adding per-op copies + callback dispatch + a less-optimized TLS fork. Decision + data: `runs/tcp-tls-backend-decision.md`. **No event-loop dependency is taken.**

### Two API shapes, one non-blocking engine
Consumers choose the *shape* that fits their code; both run on the same netpoller-backed engine:
- **Blocking pull** (`Conn.Send`/`Recv`) — goroutine-per-conn; the goroutine parks on epoll between frames. Simplest; the §5 perf targets are measured here.
- **Async push** (`Handler.OnData`, à la nbio) — the SDK runs the read loop and *calls* the consumer per frame. On the stdlib backend this is a **goroutine-per-conn facade** over the blocking port (one read-goroutine dispatches callbacks), so it has stdlib's perf and a handler may block freely. It is **not** a second event loop and buys **no** goroutine economy — that economy needs a fed-bytes TLS engine (the `llib` fork), which only a native `HandlerBackend` (e.g. a future nbio adapter) provides. The async *API* is decoupled from the engine: a deploy that one day needs O(cores) goroutines for millions of idle conns swaps in a `HandlerBackend` with no `Handler`-consumer change. Until then, push-API ergonomics ship on stdlib at stdlib speed.

### Perf levers (squeeze the hardware) — what actually moves cloud cost
Ordered by impact on the metrics that count:
1. **Allocation budget → GC pressure.** Buffer pooling (`sync.Pool`) for frame send/receive + header scratch; reuse read buffers across `Recv`. Target ≤2 allocs/op on the hot path (§5). GC CPU is the dominant hidden cloud cost in Go services; cutting allocs/op is the highest-leverage lever.
2. **TLS session resumption** (`TLSConfig.SessionResumption`). The full handshake (ECDSA ~1 ms, RSA ~2 ms of CPU) is the most expensive per-connection event. TLS 1.3 PSK / 1.2 tickets cut resumed handshakes to ~µs. Mandatory for churny workloads; client keeps an LRU session cache, server enables tickets.
3. **Connection pooling** (§9, opt-in). Amortize handshake across many exchanges — the single biggest CPU saver for request-style traffic.
4. **Hardware crypto.** TLS 1.3 + AES-128-GCM → AES-NI on x86, crypto extensions on ARM. `crypto/tls` uses them automatically; the default cipher policy keeps the AEAD path on hardware.
5. **Accept scaling** (`ServerConfig.AcceptShards`, opt-in, Linux). `SO_REUSEPORT`: N parallel accept loops on one port, kernel load-balances new conns across them → removes single-accept-loop + accept-mutex contention on many-core boxes. Scales connect/sec on high-churn ingress. Falls back to 1 shard off-Linux.
6. **Socket tuning.** `TCP_NODELAY` on by default (latency); tunable `ReadBufferSize`/`WriteBufferSize` (socket `SO_RCVBUF/SO_SNDBUF` + framer buffers) for bulk vs small-frame profiles.
7. **Vectored writes.** Coalesce frame header + payload into one write (pooled buffer); use `net.Buffers` (writev) where the path allows.

### Cloud runtime tuning (document-only; caller owns the process)
The transport stays pure I/O. Recommended process-level settings for cloud/container efficiency:
- **GOMAXPROCS** — auto-tuned to the cgroup CPU quota by **Go 1.26** (`GODEBUG=containermaxprocs`, default on). No action needed; do NOT hard-pin it. (Pre-1.26 fleets: use `automaxprocs`.) This is the #1 cloud footgun — Go seeing host cores in a quota-limited container causes scheduler thrash + CPU throttling.
- **GOMEMLIMIT** — set to ≈90% of the container memory limit so GC runs *before* the OOM-killer and stays lazy when headroom exists. The SDK's `process/cgroups` package can read the limit; the caller's `main()` applies `debug.SetMemoryLimit`. Single biggest lever against cloud OOM-kills + GC over-running.
- **GOGC** — default 100 is fine once GOMEMLIMIT is set; raise (e.g. 200) to trade memory for less GC CPU on throughput-bound services.

### Metrics that count (cloud $ mapping)
The perf-budget (§5) and gates optimize the numbers that map to spend, not vanity MB/s:
- **CPU-seconds/GB** (throughput per core) → compute cost.
- **allocs/op & B/op** → GC CPU → compute cost.
- **p99 latency** → SLO headroom → over-provisioning cost.
- **memory/connection** → connection density → node count.

## §6 Dependencies + Config Validation

**Backend decision (benchmarked):** the default transport backend is **stdlib `net` + `crypto/tls`** — zero new dependency. A fair POC benchmarked it against **nbio** (the only high-perf TCP library with native TLS; gnet/netpoll have none). Two rounds:
1. *Blocking port path* — stdlib beats nbio on throughput (~2× at 1 MiB), latency, and allocations; ties on handshake.
2. *Non-blocking at scale* — a concurrency sweep tested nbio's **native event-loop callback** mode (its real strength) vs stdlib goroutine-per-conn at N = 64…16384 active TLS-1.3 connections. **stdlib still wins throughput, p50, p99, and CPU/op at every concurrency level** (1.3–1.7× throughput, up to 2.3× better p99 tail). nbio's only edge is goroutine count (~half), which buys no performance and adds tail latency, higher CPU, and connect-burst handshake fragility.

The reason: **Go's runtime netpoller is already a non-blocking epoll loop** — stdlib `net` is not "blocking"; goroutines park on epoll and the runtime multiplexes. So the blocking `Conn.Send/Recv` port, backed by the netpoller, *is* the high-performance non-blocking model; an explicit userspace event loop on top of the same epoll only pays off at millions of idle connections (out of scope). Evidence + reproduce: `runs/tcp-tls-backend-decision.md` (incl. the concurrency-sweep addendum); benchmark repo (private): https://github.com/PremModhaOfficial/tcp-tls-backend-bench. The swappable-backend design (`Config.Backend` / `Config.BackendFactory`, §7) lets a future backend replace stdlib via an SDK update with no consumer code change.

**Candidate rejection table** (why the field narrowed to stdlib vs nbio):

| Lib | Model | Native TLS | Verdict |
|---|---|---|---|
| **stdlib `net`+`crypto/tls`** | goroutine-per-conn + netpoller | yes | **DEFAULT** — wins active traffic at every N, zero dep |
| **nbio** | userspace event loop | yes (`llib` crypto/tls fork) | rejected as default; kept as future optional `HandlerBackend` for the millions-idle-conn regime |
| **gnet** | userspace event loop | **no** (roadmap-only, confirmed upstream via DeepWiki 2026-06-03) | excluded — TLS must be hand-rolled over `OnTraffic` byte callbacks; the SDK would own a forked TLS engine, forfeiting gnet's zero-copy edge under TLS. Worse than nbio (which at least ships `llib`). |
| **netpoll** (CloudWeGo) | userspace event loop | **no** | excluded — same no-native-TLS wall as gnet |

gnet/netpoll would only be candidates for a **plaintext** high-density TCP transport (TLS terminated upstream) — not this TLS-first port.

No new third-party dependency is required; the package builds on the Go standard library plus existing in-tree packages already vetted in `go.mod`.

- `crypto/tls`, `crypto/x509`, `net` (Go 1.26 stdlib) — license: BSD-3-Clause (Go project); vuln-scan: covered by `govulncheck`; transitive count: 0 (stdlib); last-commit age: n/a (toolchain-pinned).
- `motadatagosdk/core/pool/resourcepool` (in-tree) — connection pooling; no external license impact.
- `motadatagosdk/core/circuitbreaker` (in-tree, wraps `github.com/sony/gobreaker/v2` already in `go.mod`) — dial breaker.
- `motadatagosdk/otel` + `motadatagosdk/otel/tracer|metrics|logger` (in-tree) — observability facade.

Config validation rules:
- Fail fast (`ErrTLSConfigInvalid`) if `TLS.CertFile`/`KeyFile` are set without the other, or if `ClientAuth` is true on the server without a `CAFile`/`CredentialProvider` to verify clients.
- Fail fast if `Config.Address`/`ServerConfig.Address` is empty (no implicit localhost in production paths).
- Reject `MaxFrameSize <= 0`; apply a documented default (16 MiB) when unset.
- Reject `MinVersion > MaxVersion`; reject `MinVersion < TLS 1.2`.
- `SkipVerify == true` is permitted but emits a single WARN log at construction and is forbidden when `ClientAuth` is set.
- `CipherSuites` may only be set when `MinVersion == TLS 1.2` (TLS 1.3 suites are fixed); a non-empty list under TLS-1.3-only config is rejected.

## §7 Config + API

```go
// Package tcptls provides a secure, connection-oriented byte transport over
// TCP with TLS 1.2+. It exposes stable port interfaces whose public surface
// references no crypto/tls or crypto/x509 type, so the underlying transport
// implementation can be swapped via an SDK update without consumer code changes.
package tcptls

import (
	"context"
	"net"
	"time"

	"motadatagosdk/otel/tracer"
)

// ── Neutral TLS configuration ───────────────────────────────────────────────

// TLSVersion enumerates negotiable TLS protocol versions independently of any
// transport backend. TLSVersion never aliases a crypto/tls constant.
type TLSVersion uint16

const (
	TLSVersionUnset TLSVersion = iota // TLSVersionUnset selects the package default.
	TLS12                             // TLS12 is TLS 1.2.
	TLS13                             // TLS13 is TLS 1.3.
)

// CipherSuite enumerates TLS 1.2 cipher suites the transport may negotiate.
// CipherSuite values are backend-neutral identifiers mapped internally; they
// apply only when MinVersion is TLS12 (TLS 1.3 suites are fixed by the protocol).
type CipherSuite uint16

// TLSConfig holds backend-neutral TLS settings. It is mapped to the active
// backend internally; no field exposes a crypto/tls or crypto/x509 type.
type TLSConfig struct {
	MinVersion   TLSVersion         // MinVersion is the lowest acceptable version (default TLS12).
	MaxVersion   TLSVersion         // MaxVersion is the highest acceptable version (default TLS13).
	CertFile     string             // CertFile is the PEM certificate path (server: required; client: required for mTLS).
	KeyFile      string             // KeyFile is the PEM private-key path paired with CertFile.
	CAFile       string             // CAFile is the PEM CA bundle used to verify the peer.
	ServerName   string             // ServerName is the SNI / verification hostname (client side).
	ClientAuth   bool               // ClientAuth, on a server, requires and verifies a client certificate (mTLS).
	CipherSuites []CipherSuite      // CipherSuites overrides defaults; valid only when MinVersion is TLS12.
	SkipVerify   bool               // SkipVerify disables peer verification; development only, logged as WARN.
	Credentials  CredentialProvider // Credentials, if set, supplies certs/roots at handshake time and overrides the *File fields.
	SessionResumption bool          // SessionResumption enables TLS 1.3 PSK / 1.2 ticket resumption to cut handshake CPU. Recommended on.
}

// CredentialProvider supplies certificates and trust roots at handshake time,
// enabling rotation without reconnecting established connections.
type CredentialProvider interface {
	// ServerCertificate returns the server certificate to present for hello.
	ServerCertificate(ctx context.Context, hello ClientHelloInfo) (Certificate, error)
	// ClientCertificate returns the client certificate to present for mTLS.
	ClientCertificate(ctx context.Context, req CertRequest) (Certificate, error)
	// RootCAs returns the current set of trust roots used to verify the peer.
	RootCAs(ctx context.Context) (CertPool, error)
}

// Certificate is an opaque, backend-neutral handle to a parsed key pair.
type Certificate struct{ /* opaque */ }

// CertPool is an opaque, backend-neutral set of trusted CA certificates.
type CertPool struct{ /* opaque */ }

// ClientHelloInfo carries the backend-neutral subset of a TLS ClientHello
// needed to select a server certificate (SNI, offered versions).
type ClientHelloInfo struct {
	ServerName string // ServerName is the SNI value sent by the client.
}

// CertRequest carries the backend-neutral hints a server sends when requesting
// a client certificate during mTLS.
type CertRequest struct {
	AcceptableCAs []string // AcceptableCAs lists CA subject names the server will accept.
}

// ConnectionState reports the negotiated security parameters of a connection
// using neutral types only.
type ConnectionState struct {
	Version           TLSVersion  // Version is the negotiated TLS version.
	CipherSuite       CipherSuite // CipherSuite is the negotiated cipher suite.
	PeerCertSubjects  []string    // PeerCertSubjects lists the peer certificate chain subjects.
	NegotiatedProto   string      // NegotiatedProto is the ALPN protocol, empty if none.
	HandshakeComplete bool        // HandshakeComplete reports whether the handshake finished.
}

// ── Client / server configuration ───────────────────────────────────────────

// Config configures a dialing client.
type Config struct {
	Address           string             // Address is the remote "host:port" to dial. Required.
	TLS               TLSConfig          // TLS holds the neutral TLS settings. Transport is TLS-only.
	DialTimeout       time.Duration      // DialTimeout bounds one dial+handshake attempt (default 10s).
	MaxFrameSize      int                // MaxFrameSize caps an inbound frame in bytes (default 16 MiB).
	ReadBufferSize    int                // ReadBufferSize sizes socket SO_RCVBUF + receive framer buffer (0 = OS default).
	WriteBufferSize   int                // WriteBufferSize sizes socket SO_SNDBUF + send coalescing buffer (0 = OS default).
	KeepAlive         time.Duration      // KeepAlive sets the TCP keep-alive period (0 = OS default, <0 = off).
	Pool              PoolConfig         // Pool configures connection pooling; zero value disables it.
	Retry             RetryConfig        // Retry configures dial retry; zero value disables it.
	Breaker           BreakerConfig      // Breaker configures a dial circuit breaker; zero value disables it.
	ALPNProtocols     []string           // ALPNProtocols advertises application-layer protocol IDs at the handshake; empty disables ALPN.
	Backend           string             // Backend selects the implementation; "" selects the default "std" (stdlib net+crypto/tls, chosen by benchmark — see §6).
	BackendFactory    BackendFactory     // BackendFactory, if set, overrides Backend with an injected implementation.
	ObservabilityName string             // ObservabilityName is the low-cardinality component name for spans/metrics.
	TracerProvider    tracer.Provider    // TracerProvider opts in a specific provider; nil uses the SDK facade global.
}

// ServerConfig configures a listening server.
type ServerConfig struct {
	Address           string
	TLS               TLSConfig     // TLS must carry a server certificate; ClientAuth enables mTLS.
	MaxFrameSize      int
	AcceptShards      int           // AcceptShards sets parallel SO_REUSEPORT accept loops (Linux; 0/1 = single). Scales connect/sec on many-core boxes.
	ReadBufferSize    int           // ReadBufferSize sizes socket SO_RCVBUF + receive framer buffer (0 = OS default).
	WriteBufferSize   int           // WriteBufferSize sizes socket SO_SNDBUF + send coalescing buffer (0 = OS default).
	ALPNProtocols     []string      // ALPNProtocols lists protocols the server selects from; empty disables ALPN.
	Backend           string
	BackendFactory    BackendFactory
	ObservabilityName string
	TracerProvider    tracer.Provider
}

// PoolConfig configures client-side connection pooling, layered on
// core/pool/resourcepool. A zero MaxSize disables pooling.
type PoolConfig struct {
	MinSize     int           // MinSize is the number of warm connections kept ready.
	MaxSize     int           // MaxSize caps total pooled connections; 0 disables pooling.
	IdleTimeout time.Duration // IdleTimeout evicts connections idle longer than this.
	AcquireWait time.Duration // AcquireWait bounds the wait for a free connection before ErrPoolExhausted.
}

// RetryConfig configures dial retry with exponential backoff and jitter.
type RetryConfig struct {
	MaxAttempts     int           // MaxAttempts caps dial attempts; <=0 disables retry.
	InitialInterval time.Duration // InitialInterval is the first backoff delay.
	MaxInterval     time.Duration // MaxInterval caps the backoff delay.
	Multiplier      float64       // Multiplier scales the delay each attempt.
	Jitter          float64       // Jitter is the random fraction (0.0–1.0) applied to each delay.
}

// BreakerConfig configures a dial circuit breaker over core/circuitbreaker.
type BreakerConfig struct {
	FailureThreshold int           // FailureThreshold opens the breaker after this many failures in Window.
	Window           time.Duration // Window is the rolling failure-count window.
	RecoveryTimeout  time.Duration // RecoveryTimeout is how long the breaker stays open before half-open.
	HalfOpenMax      int           // HalfOpenMax is the probe count allowed in half-open.
}

// ── Backend swap mechanism (advanced) ────────────────────────────────────────

// Backend is the driven port implemented by a transport adapter. The default
// "std" backend (net + crypto/tls) is compiled in and selected when Backend is
// "" and BackendFactory is nil. Alternative implementations are injected via
// BackendFactory; the package keeps no global registry and defines no init().
type Backend interface {
	// DialConn establishes a raw secured connection for the client role.
	DialConn(ctx context.Context, cfg Config) (rawConn, error)
	// ListenConn binds a listener for the server role.
	ListenConn(ctx context.Context, cfg ServerConfig) (rawListener, error)
}

// BackendFactory constructs a Backend. Injecting a factory swaps the transport
// implementation with no change to the Config/Conn/Client/Listener contract.
type BackendFactory func() (Backend, error)

// HandlerBackend is an OPTIONAL capability a Backend may implement to dispatch
// the async Handler callbacks natively — e.g. an event-loop adapter that serves
// the same OnConn/OnData/OnClose with O(cores) goroutines instead of one per
// connection. When a Backend does NOT implement HandlerBackend, the package
// drives Handler via a goroutine-per-conn loop over the blocking raw port, with
// identical observable behavior. This is the seam that lets an event-loop
// backend (e.g. a future nbio adapter, for the millions-idle-conn regime) be
// swapped in via an SDK update with NO Handler-consumer code change.
type HandlerBackend interface {
	Backend
	// ServeListener binds and runs an async dispatch loop, delivering each
	// connection's lifecycle to h. It returns once the listener is closed.
	ServeListener(ctx context.Context, cfg ServerConfig, h Handler) error
}

// ── Stable ports ─────────────────────────────────────────────────────────────

// Conn is a framed, secured, full-duplex connection. All methods take a context
// first and honor its deadline and cancellation.
type Conn interface {
	// Send writes payload as one length-prefixed frame.
	Send(ctx context.Context, payload []byte) error
	// Recv reads the next full frame, returning ErrFrameTooLarge if it exceeds MaxFrameSize.
	Recv(ctx context.Context) ([]byte, error)
	// ConnectionState reports negotiated TLS parameters using neutral types.
	ConnectionState() ConnectionState
	// RemoteAddr returns the peer address.
	RemoteAddr() net.Addr
	// LocalAddr returns the local address.
	LocalAddr() net.Addr
	// Close releases the connection, returning it to the pool if pooled. Idempotent.
	Close(ctx context.Context) error
}

// Client dials secured connections to Config.Address.
type Client interface {
	// Connect returns a ready framed Conn, drawn from the pool if pooling is enabled.
	Connect(ctx context.Context) (Conn, error)
	// Close drains the pool and releases client resources. Idempotent.
	Close(ctx context.Context) error
	// Stats returns transport and pool counters.
	Stats() Stats
}

// Listener accepts inbound secured connections.
type Listener interface {
	// Accept returns the next inbound Conn after a completed handshake (pull model).
	Accept(ctx context.Context) (Conn, error)
	// Serve runs the async push model: it accepts connections and dispatches each
	// one's lifecycle to h (OnConn, then OnData per frame, then OnClose). It blocks
	// until ctx is cancelled or the listener is closed. Use EITHER Accept or Serve
	// on a given Listener, not both. If the active backend implements
	// HandlerBackend, dispatch is native (event-loop); otherwise the SDK runs a
	// goroutine-per-conn facade — identical behavior, stdlib performance.
	Serve(ctx context.Context, h Handler) error
	// Addr returns the bound local address.
	Addr() net.Addr
	// Close stops accepting and releases the listener. Idempotent.
	Close(ctx context.Context) error
}

// ── Async push port (Handler) ────────────────────────────────────────────────

// Handler is the async, callback-style consumption port — an alternative to the
// blocking Conn.Send/Recv pull API, modeled on event-loop libraries (nbio).
// Events for one connection are delivered in order. On the default stdlib
// backend each connection gets its own dispatch goroutine, so a handler MAY
// block (do I/O, call Conn.Send to reply) without stalling other connections.
type Handler interface {
	// OnConn fires once after a completed handshake. c may be retained and used
	// to Send replies; do not call Recv on it (the dispatch loop owns reads).
	OnConn(c Conn)
	// OnData fires for each received frame, in order. frame is a pooled buffer
	// valid ONLY for the duration of the call — copy it to retain past return.
	OnData(c Conn, frame []byte)
	// OnClose fires exactly once when the connection ends; err is the terminal
	// cause (nil on clean close, e.g. io.EOF-equivalent ErrConnClosed otherwise).
	OnClose(c Conn, err error)
}

// HandlerFunc adapts a plain per-frame function into a Handler with no-op
// OnConn/OnClose, for the common "just process frames" case:
//
//	lis.Serve(ctx, tcptls.HandlerFunc(func(c tcptls.Conn, frame []byte) {
//	    _ = c.Send(ctx, process(frame))
//	}))
type HandlerFunc func(c Conn, frame []byte)

// OnConn implements Handler (no-op).
func (HandlerFunc) OnConn(Conn) {}

// OnData implements Handler by calling the wrapped function.
func (f HandlerFunc) OnData(c Conn, frame []byte) { f(c, frame) }

// OnClose implements Handler (no-op).
func (HandlerFunc) OnClose(Conn, error) {}

// Stats reports point-in-time transport counters.
type Stats struct {
	ActiveConns int64 // ActiveConns is the count of currently open connections.
	PoolIdle    int64 // PoolIdle is the count of idle pooled connections.
	DialTotal   int64 // DialTotal is the cumulative dial count.
	DialErrors  int64 // DialErrors is the cumulative failed-dial count.
}

// ── Constructors ─────────────────────────────────────────────────────────────

// Dial validates cfg, resolves the backend, and returns a Client. It does not
// open a connection until Client.Connect is called (unless Pool.MinSize > 0).
func Dial(ctx context.Context, cfg Config) (Client, error)

// Listen validates cfg, resolves the backend, binds the address, and returns a Listener.
func Listen(ctx context.Context, cfg ServerConfig) (Listener, error)

// DefaultPoolConfig returns a PoolConfig with production-sane pooling defaults,
// for one-line opt-in: Config{Pool: DefaultPoolConfig()}.
func DefaultPoolConfig() PoolConfig

// ServeConn drives a single already-connected Conn with the async push model:
// it reads frames and dispatches OnData (and finally OnClose) to h, blocking
// until ctx is cancelled or the connection ends. This is the client-side
// counterpart to Listener.Serve — dial with Client.Connect, then hand the Conn
// to ServeConn for callback-style consumption instead of looping Recv.
func ServeConn(ctx context.Context, c Conn, h Handler) error

// ── Sentinel errors (errors.Is) ──────────────────────────────────────────────

var (
	ErrNotConnected     error // ErrNotConnected indicates an operation on a connection that is not established.
	ErrHandshakeFailed  error // ErrHandshakeFailed indicates the TLS handshake did not complete.
	ErrFrameTooLarge    error // ErrFrameTooLarge indicates an inbound frame exceeded MaxFrameSize.
	ErrConnClosed       error // ErrConnClosed indicates use of a closed connection.
	ErrDialTimeout      error // ErrDialTimeout indicates a dial attempt exceeded DialTimeout.
	ErrPoolExhausted    error // ErrPoolExhausted indicates no pooled connection became available within AcquireWait.
	ErrTLSConfigInvalid error // ErrTLSConfigInvalid indicates a malformed or insecure TLS configuration.
	ErrUnknownBackend   error // ErrUnknownBackend indicates Config.Backend names no compiled-in adapter.
	ErrPeerCertRejected error // ErrPeerCertRejected indicates peer certificate verification failed.
	ErrCircuitOpen      error // ErrCircuitOpen indicates the dial circuit breaker is open.
	ErrALPNMismatch     error // ErrALPNMismatch indicates no mutually-acceptable ALPN protocol was negotiated.
)
```

<!-- Generated symbols will be stamped with [traces-to: TPRD-§7-<id>] (G99/G102/G103). Do not author markers by hand. -->

## §8 Observability

### Spans
| Span name | Attributes |
|---|---|
| `motadata.tcptls.dial` | `net.peer.name`, `net.peer.port`, `tls.version`, `backend` |
| `motadata.tcptls.handshake` | `tls.version`, `tls.cipher`, `tls.resumed`, `mtls` |
| `motadata.tcptls.accept` | `net.host.name`, `net.host.port`, `tls.version`, `mtls` |

`Send`/`Recv` are intentionally metrics-only (per-frame spans would be high-volume); span names are static and low-cardinality. The async `Handler` path reuses the same `accept`/`handshake` spans and the `frames.*`/`bytes.*` counters — `OnData` dispatch is metrics-only (no per-callback span), so the two consumption models are observability-equivalent.

### Metrics
| Metric | Type | Unit | Labels |
|---|---|---|---|
| `motadata.tcptls.connections.active` | gauge | `{connections}` | `role` (client/server), `backend` |
| `motadata.tcptls.dial.duration` | histogram | `ms` | `backend`, `outcome` |
| `motadata.tcptls.handshake.duration` | histogram | `ms` | `role`, `tls.version`, `outcome` |
| `motadata.tcptls.frames.sent` | counter | `{frames}` | `role` |
| `motadata.tcptls.frames.received` | counter | `{frames}` | `role` |
| `motadata.tcptls.bytes.sent` | counter | `By` | `role` |
| `motadata.tcptls.bytes.received` | counter | `By` | `role` |
| `motadata.tcptls.pool.acquire.duration` | histogram | `ms` | `outcome` |
| `motadata.tcptls.errors` | counter | `{errors}` | `kind` (handshake/frame/dial/pool) |

Trace propagation strategy: via the `motadatagosdk/otel` facade (`tracer.Start`); never the raw upstream OTel SDK. The transport carries opaque bytes and does **not** inject/extract trace headers into the frame stream (that is the consumer protocol's concern).

## §9 Resilience
- **Retry** (dial only): `RetryConfig.MaxAttempts`, base `InitialInterval`, max `MaxInterval`, exponential `Multiplier` with `Jitter`. Retryable: connection-refused, timeout, transient network errors. Non-retryable: `ErrTLSConfigInvalid`, `ErrPeerCertRejected`, context cancellation, unknown-backend.
- **Circuit breaker** (dial only, via `core/circuitbreaker`): opens after `FailureThreshold` failures within `Window`; stays open for `RecoveryTimeout`; allows `HalfOpenMax` probes; open state short-circuits with `ErrCircuitOpen`.
- **Connection pool** (client, via `core/pool/resourcepool`): min `PoolConfig.MinSize`, max `MaxSize`, idle eviction `IdleTimeout`; acquisition blocks up to `AcquireWait` then returns `ErrPoolExhausted`; broken connections are destroyed on return and lazily recreated on next acquire.
- **Async handler backpressure**: on the stdlib backend, each connection's read loop calls `OnData` synchronously, so a slow handler **naturally backpressures** that one connection (the socket read blocks → TCP flow-control throttles the peer) **without** stalling other connections (each has its own goroutine). Handlers must not retain the `OnData` frame past return (pooled buffer; copy to retain) and should offload long work to their own goroutine if they want to decouple processing from read cadence — the SDK does not buffer unboundedly on their behalf (no hidden per-conn queue → no unbounded memory growth under a slow consumer).

## §10 Security
- **TLS / mTLS plan**: required floor TLS 1.2, TLS 1.3 negotiated when available; SNI via `ServerName`; custom CA via `CAFile` or `CredentialProvider.RootCAs`; mTLS when `ClientAuth` is set (server verifies client cert; client presents cert via `CertFile`/`KeyFile` or provider).
- **Credential provider**: file-based by default; rotation via `CredentialProvider` (file-with-reload or external source). Never plaintext credentials in source (G69). Integration tests read cert paths from `.env`/`.env.example` fixtures, never embedded keys.
- **Auth scheme**: mTLS (mutual certificate) for peer authentication; the transport itself carries no bearer/API-key concept (application-layer concern).
- **Input validation**: `MaxFrameSize` bounds inbound frames (DoS guard, fuzz-tested); length prefix validated before allocation; `SkipVerify` gated + WARN-logged and disallowed under `ClientAuth`; insecure version/cipher combinations rejected at construction with `ErrTLSConfigInvalid`.

## §11 Testing
- **Unit**: table-driven cases per public method (`Dial`, `Listen`, `Connect`, `Accept`, `Send`, `Recv`, `Close`, config validation matrix); coverage ≥ 90% on the new package (G60). Mocks via the `go-client-mock-strategy` backend seam (`BackendFactory`).
- **Integration**: in-process client↔server over loopback TLS using generated test certs (RSA + ECDSA, valid/expired/wrong-CA), plus mTLS accept/reject paths; image-pinned external peer (e.g. `openssl s_server`) via testcontainers for cross-stack interop. Cert versions/fixtures pinned.
- **Async handler port**: `Listener.Serve` + `ServeConn` + `Handler`/`HandlerFunc` covered — OnConn/OnData/OnClose ordering and once-only OnClose; pooled-frame reuse safety (handler that retains without copying is caught); slow-handler backpressure isolates one conn (others keep flowing); a stub `HandlerBackend` proves native dispatch produces behavior identical to the goroutine-per-conn facade (the swap-equivalence invariant).
- **Benchmarks**: per hot-path symbol (`Send`, `Recv`, pooled `Connect`); allocation reporting on (G104); benchstat regression compare vs baseline (G65); paired `[constraint:]` benches for §5 targets.
- **Fuzz**: frame parser / length-prefix decoder with crash-triage workflow (malformed prefixes, truncated frames, oversize claims).
- **Leak**: `goleak` harness clean across dial/accept/close cycles (G63); no goroutine or connection leak after `Close`.
- **Flake hunt**: `-count=N` on the integration suite; flake hunter at T3 (handshake timing, pool races).

## §12 Breaking-Change Risk

**Mode A: no breaking changes (new exports only).** The package `motadatagosdk/transport/tcptls` is additive; no existing exported symbol is changed or removed. Semver implication: **MINOR**. Each new exported symbol pairs with a `[stable-since: vX.Y.Z]` decision (G101) at first release. Agrees with §1.

## §13 Rollout
- **H1 (TPRD approval)**: TPRD complete, manifests resolve, `§Target-Language: go` resolves to a pack manifest, all §14 blockers resolved (notably the target-branch question).
- **H5 (design)**: API stub passes design devils (semver, convention, security, over-engineering, dep-vet); `design/perf-budget.md` authored from §5; the backend-swap seam reviewed for the zero-stdlib-leak invariant.
- **H7 (impl)**: code passes impl devils + leak/marker/constraint scans, ≥ 90% coverage, zero `TODO`/`ErrNotImplemented`, every §7 symbol has impl + test + doc-comment + (hot-path) bench + runnable `Example_*`.
- **H9 (testing)**: perf-confidence gates pass — regression, oracle, allocation, complexity, drift, MMD soak; interop integration green.
- **H10 (merge)**: final diff reviewed; learning-notifications acknowledged; merge recommendation on `sdk-pipeline/<run-id>`.

## §14 Pre-Phase-1 Clarifications
- **OQ-001 [RESOLVED]**: Base branch for the pipeline's `sdk-pipeline/<run-id>` working branch. — **ANSWER**: `origin/NATS_Updated` (confirmed present after `git fetch`; the requested name was `NATS_Update`, actual remote ref is `NATS_Updated`). **Blocker**: NO (resolved).
- **OQ-002 [RESOLVED]**: Should the transport optionally integrate `core/codec` for typed message framing, or remain bytes-only at v1? — **ANSWER**: No — bytes-only v1; callers compose codec at the call site (`conn.Send(ctx, codec.Pack(v))`). Rationale: bytes API already supports any codec for free; baking codec in adds no capability, only couples a wire-contract into the SDK. See §2 Non-Goals. **Blocker**: NO.
- **OQ-003 [RESOLVED]**: ALPN — configurable input or read-only? — **ANSWER**: Configurable via `ALPNProtocols []string` on `Config`/`ServerConfig`, **default empty** (empty = no advertise, behaves as read-only; `ConnectionState.NegotiatedProto` always reports). Rationale: empty default matches read-only behavior at zero cost while providing the TLS-layer protocol-version negotiation lever for mixed-SDK-version fleets. `ErrALPNMismatch` on no common protocol. **Blocker**: NO.
- **OQ-005 [RESOLVED]**: Which TCP networking library backs the default backend? — **ANSWER**: stdlib `net` + `crypto/tls`, chosen by benchmark POC (see §6 + `runs/tcp-tls-backend-decision.md`, repo https://github.com/PremModhaOfficial/tcp-tls-backend-bench). **Blocker**: NO.
- **OQ-006 [RESOLVED]**: Should a handler/streaming push port be added (async `OnData` callbacks, à la nbio)? — **ANSWER**: **Yes — added (FR-20/FR-21), but justified on ergonomics + swap-readiness, NOT performance.** The perf question is settled the other way: a concurrency sweep (N = 64…16384 active conns) benched nbio's native callback mode directly and stdlib goroutine-per-conn won throughput, p50, p99, and CPU/op at every level (Go's netpoller is already non-blocking epoll), so the push port is **not warranted on perf grounds** and ships on the stdlib backend as a goroutine-per-conn facade (no goroutine economy — that needs a fed-bytes TLS engine). It IS warranted because (a) many consumers prefer an async push API shape, and (b) the `Handler` + optional `HandlerBackend` seam is exactly what lets a future event-loop backend (nbio) be swapped in for the **millions-idle-conn** regime with zero consumer code change — the swap guarantee extended to the consumption model itself. The API shape is decoupled from the engine. See §Perf-Engineering "Two API shapes, one non-blocking engine" + `runs/tcp-tls-backend-decision.md` addendum. **Blocker**: NO.
- **OQ-004 [RESOLVED]**: Client connection pooling default. — **ANSWER**: **Opt-in / default off** — zero `PoolConfig` disables pooling; `DefaultPoolConfig()` gives one-line opt-in. Rationale: the framed transport has no request/response boundary, so default-on would expose a stale-frame cross-talk hazard to callers who never configured pooling; opt-in confines that edge to deliberate users. **Blocker**: NO.

- **OQ-007 [RESOLVED]**: Accept scaling — single acceptor or SO_REUSEPORT sharding? — **ANSWER**: opt-in `ServerConfig.AcceptShards` (SO_REUSEPORT, Linux; falls back to 1 elsewhere). Removes single-accept-loop + accept-mutex contention on many-core cloud boxes. See §Perf-Engineering. **Blocker**: NO.
- **OQ-008 [RESOLVED]**: Who owns cloud runtime tuning (GOMAXPROCS/GOMEMLIMIT/GOGC)? — **ANSWER**: document-only; transport stays pure I/O. GOMAXPROCS is auto in Go 1.26 (cgroup-aware); GOMEMLIMIT/GOGC are caller-applied in `main()` per §Perf-Engineering guidance (SDK `process/cgroups` can read the limit). **Blocker**: NO.

<!-- Any OQ with Blocker: YES that is unresolved at preflight → exit 4. Cap of 5 clarifying questions in Wave I4. -->

## §Skills-Manifest
| Skill | Min version | Why required |
|---|---|---|
| go-client-tls-configuration | 1.0.0 | FR-TCPTLS-03, FR-TCPTLS-15, §10 |
| go-hexagonal-architecture | 1.0.0 | FR-TCPTLS-06 (backend swap seam) |
| go-struct-interface-design | 1.0.0 | §7 ports (Conn/Client/Listener; Handler/HandlerBackend, FR-TCPTLS-20/21) |
| go-sdk-config-struct-pattern | 1.0.0 | §7 Config/ServerConfig + constructors |
| go-credential-provider-pattern | 1.0.0 | FR-TCPTLS-10 (cert rotation) |
| go-connection-pool-tuning | 1.0.0 | FR-TCPTLS-07, §9 pool |
| go-circuit-breaker-policy | 1.0.0 | FR-TCPTLS-09, §9 breaker |
| go-idempotent-retry-patterns | 1.0.0 | FR-TCPTLS-08, §9 retry |
| go-context-deadline-patterns | 1.0.0 | FR-TCPTLS-05 (ctx-first I/O) |
| go-client-shutdown-lifecycle | 1.0.0 | FR-TCPTLS-14 (graceful Close) |
| go-backpressure-flow-control | 1.0.0 | §5 throughput, framed Send/Recv, FR-TCPTLS-20 (Handler dispatch backpressure, §9) |
| go-error-handling-patterns | 1.0.0 | FR-TCPTLS-12 (sentinels) |
| go-otel-instrumentation | 1.0.0 | FR-TCPTLS-13, §8 |
| go-sdk-otel-hook-integration | 1.0.0 | §8 facade provider opt-in |
| go-table-driven-tests | 1.0.0 | §11 unit |
| go-tdd-patterns | 1.0.0 | §11 red/green/refactor |
| go-fuzz-patterns | 1.0.0 | §11 frame-parser fuzz |
| go-testcontainers-setup | 1.0.0 | §11 interop integration |
| goroutine-leak-prevention | 1.0.0 | §11 leak (G63) |
| go-client-mock-strategy | 1.0.0 | §11 backend-seam mocks |
| go-example-function-patterns | 1.0.0 | runnable `Example_*` per symbol |
| go-module-paths | 1.0.0 | package path `transport/tcptls` |

<!-- G23 (WARN-only): each skill must exist in skills/skill-index.json at version ≥ declared. Misses auto-file to docs/PROPOSED-SKILLS.md. -->

## §Guardrails-Manifest
| Guardrail | Applies to | Enforcement |
|---|---|---|
| G01 | all | BLOCKER |
| G20 | intake | BLOCKER |
| G21 | intake | BLOCKER |
| G23 | intake | WARN |
| G24 | intake | BLOCKER |
| G07 | all | BLOCKER |
| G69 | design+impl | BLOCKER |
| G30 | testing | BLOCKER |
| G31 | testing | BLOCKER |
| G32 | testing | BLOCKER |
| G33 | testing | BLOCKER |
| G34 | testing | BLOCKER |
| G38 | impl | BLOCKER |
| G40 | impl | BLOCKER |
| G41 | impl | BLOCKER |
| G42 | impl | BLOCKER |
| G43 | impl | BLOCKER |
| G48 | impl | BLOCKER |
| G60 | testing | BLOCKER |
| G61 | testing | BLOCKER |
| G63 | testing | BLOCKER |
| G65 | testing | BLOCKER |
| G70 | impl+testing | BLOCKER |
| G95 | impl | BLOCKER |
| G96 | impl | BLOCKER |
| G97 | testing | BLOCKER |
| G98 | impl | BLOCKER |
| G99 | impl | BLOCKER |
| G100 | impl | BLOCKER |
| G101 | impl | BLOCKER |
| G102 | impl | BLOCKER |
| G103 | impl | BLOCKER |
| G104 | impl (M3.5) | BLOCKER |
| G105 | testing (soak) | BLOCKER |
| G107 | testing (T5) | BLOCKER |
| G109 | impl (M3.5) | BLOCKER |

<!-- G24 (BLOCKER): each declared G-id must have an executable script at scripts/guardrails/<G-id>.sh. Missing script → exit 6; entry filed to docs/PROPOSED-GUARDRAILS.md. -->

## §Docs-Manifest
targets:
  - src/motadatagosdk/transport/tcptls/
skip: false
examples_allowed: false

## §Versioning
bump: MINOR
reasoning: "Adds new public package motadatagosdk/transport/tcptls with new exported symbols only; removes or renames nothing."
confirmed: false

## §OTel — Observability Contract

### Signals
- signals.traces: on
- signals.metrics: on
- signals.logs: on

### Provider integration
- consumer_provider_optin: yes
- facade_used_go: motadatagosdk/otel
- facade_used_python: not-applicable

### Attributes — sensitive value forbid-list
- forbidden_attributes:
  - tenant_id
  - user.id
  - password
  - token
  - api_key
  - secret
  - tls.private_key
  - client.certificate

### Declared identifiers
- declared_metric_ids:
  - motadata.tcptls.connections.active
  - motadata.tcptls.dial.duration
  - motadata.tcptls.handshake.duration
  - motadata.tcptls.frames.sent
  - motadata.tcptls.frames.received
  - motadata.tcptls.bytes.sent
  - motadata.tcptls.bytes.received
  - motadata.tcptls.pool.acquire.duration
  - motadata.tcptls.errors
- declared_span_names:
  - motadata.tcptls.dial
  - motadata.tcptls.handshake
  - motadata.tcptls.accept

### Logging
- log_correlation: required

### Surface
- nats_surface: no

### Tenant attribution
- tenant_attribution: none
