---
title: "Add Pipe (local IPC) Transport to motadata-go-sdk"
author: "thadanisahil2@gmail.com"
date: "2026-06-02"
---

§Target-Language: go
§Target-Tier: T1
§Required-Packages:
  - "shared-core@>=1.0.0"
  - "go@>=1.0.0"

# Technical Product Requirements Document — Pipe / Local-IPC Transport (`transport/pipe`)

## §1 Request Type

**Mode A (greenfield new package).** Adds a new package `motadatagosdk/transport/pipe` providing a connection-oriented, framed, **same-host inter-process** byte transport over Unix domain sockets (Linux/macOS) and Windows named pipes, for both client (dial) and server (listen) roles. No existing exported symbol is modified or removed. Agrees with §12 (new exports only → MINOR bump).

## §2 Scope

### In-Scope
- A neutral, swappable local-IPC transport exposing **stable port interfaces** (`Conn`, `Client`, `Listener`) plus a `Config`/`ServerConfig` + constructor (`Dial`, `Listen`) entrypoint, per the SDK `Config struct + constructor` convention.
- **Cross-platform parity behind one API** (build-tag adapters, mirroring `process/winjob` + `process/cgroups`): on Unix a `net` Unix-domain-socket (`SOCK_STREAM`) adapter; on Windows a `github.com/Microsoft/go-winio` named-pipe adapter. Both yield `net.Conn`/`net.Listener`, so the public surface references **no** OS-specific type. Consumer code is identical across OSes.
- **Logical addressing**: `Config.Name` is an OS-neutral endpoint name (e.g. `"motadata-agent"`); a `Endpoint(name)` helper resolves it to the OS-correct address (Unix: a pathname socket under a configurable dir, e.g. `/run/motadata/motadata-agent.sock`; Windows: `\\.\pipe\motadata-agent`). A raw `Config.Address` escape hatch overrides the mapping.
- **Framed message I/O**: length-prefixed `Send([]byte)` / `Recv() []byte` with a `MaxFrameSize` memory-exhaustion guard. SDK owns framing (matches `transport/tcptls`).
- **Peer-credential authentication** — the local-IPC analog of mTLS: `Conn.PeerCredentials()` returns the connected peer's identity (Unix: `SO_PEERCRED` → uid/gid/pid; Windows: named-pipe client process id / token user SID). An optional `Authorizer` hook on the server rejects unauthorized peers before the first frame.
- **Endpoint access control**: Unix socket file mode + parent-dir permissions; Windows security descriptor (SDDL) via the go-winio `PipeConfig`.
- Client roles: dial with per-attempt timeout, optional dial retry with backoff+jitter (peer-not-yet-up is the common IPC failure), optional circuit breaker on dial (reusing `core/circuitbreaker`), optional connection pooling (reusing `core/pool/resourcepool`).
- Server roles: `Listen`/`Accept`; stale-socket reclaim on Unix (`Listen` removes a dead socket file whose listener is gone).
- Backend injection seam (`Config.BackendFactory`) admitting an in-memory `net.Pipe` adapter for hermetic unit tests; no global registry, no `init()`.
- OTel spans + metrics via the `motadatagosdk/otel` facade; never raw upstream OTel.
- Sentinel errors matched with `errors.Is`, re-exported at package root.

### Non-Goals
- **No TLS / encryption.** The channel is same-host and kernel-mediated; confidentiality is provided by filesystem/pipe ACLs + peer-credential authn, not cryptography. (A remote secured byte transport is `transport/tcptls`'s job.)
- **No cross-host / network transport** — `transport/pipe` is loopback-only by construction (UDS path / `\\.\pipe`). Remote links use `transport/tcptls`, `transport/quicdatagram`, or `transport/http*`.
- **No application-layer protocol** (no RPC, no request/reply semantics, no service mesh). This is a transport, not a protocol stack.
- **No FIFO / `mkfifo` / anonymous `os.Pipe` mode** — unidirectional, connectionless, peer-auth-less; it would force a divergent per-OS API. See `runs/pipe-transport-backend-decision.md` §1.
- **No multi-tenancy logic** — tenant context is caller-supplied; the SDK never sets `tenant_id` (G38).
- **No serialization / codec layer** — bytes-only (`Send([]byte)`/`Recv() []byte`); callers compose any codec (`core/codec`, msgpack, JSON) at the call site.
- **No consumer-visible OS-specific type** (`*net.UnixConn`, go-winio `PipeConn`, `syscall.*`) on the public API — that coupling would defeat the cross-platform-parity guarantee.

## §3 Motivation

Motadata agents and collectors increasingly run **co-located processes** — an agent supervising plugin/poller subprocesses, a sidecar control channel, a metrics fan-in from short-lived workers — where a NATS broker hop or even a loopback TCP+TLS handshake is pure overhead. Today each such link is hand-rolled: `net.Dial("unix", …)` on Linux, a separate go-winio path on Windows, duplicated framing, peer-auth, retry, and observability wiring, with `// +build` skew that breaks the Windows build. Centralizing a single cross-platform local-IPC transport behind a stable port lets every co-located component talk over the fastest same-host channel the OS offers (benchmarked ~2.2 µs one-way on UDS, ~2.6× faster than TCP loopback — `runs/pipe-transport-backend-decision.md`) with one code path, kernel-enforced peer authentication, and SDK-standard OTel — and lets the platform team tune the underlying primitive via an SDK update without touching the fleet.

## §4 Functional Requirements

| ID | Description | Priority | §7 Symbol |
|---|---|---|---|
| FR-PIPE-01 | `Dial` connects to the endpoint named by `Config.Name`/`Address` and returns a ready framed `Conn`. | Must | `Dial`, `Client.Connect` |
| FR-PIPE-02 | `Listen` binds `ServerConfig.Name`/`Address` and `Accept` returns inbound connections; on Unix it reclaims a stale socket file whose owning listener is gone. | Must | `Listen`, `Listener.Accept` |
| FR-PIPE-03 | One public API spans both OSes: a Unix-domain-socket adapter (Unix) and a go-winio named-pipe adapter (Windows), selected at build time; no OS-specific type appears on the public surface. | Must | `Conn`, `Client`, `Listener`, `Endpoint` |
| FR-PIPE-04 | `Send`/`Recv` use length-prefixed framing; `Recv` rejects frames larger than `Config.MaxFrameSize` with `ErrFrameTooLarge`. | Must | `Conn.Send`, `Conn.Recv` |
| FR-PIPE-05 | All I/O methods take `context.Context` first and honor deadline + cancellation. | Must | `Conn.Send`, `Conn.Recv`, `Client.Connect`, `Listener.Accept` |
| FR-PIPE-06 | `Conn.PeerCredentials` returns the connected peer's OS identity (Unix uid/gid/pid via `SO_PEERCRED`; Windows client process id + user SID); a server-side `Authorizer` may reject a peer before its first frame with `ErrPeerUnauthorized`. | Must | `Conn.PeerCredentials`, `PeerCredentials`, `Authorizer`, `ErrPeerUnauthorized` |
| FR-PIPE-07 | Endpoint access control is enforced: Unix socket file mode (`SocketMode`, default `0600`) + parent dir; Windows security descriptor (`SecurityDescriptor` SDDL) on the pipe. | Must | `ServerConfig.SocketMode`, `ServerConfig.SecurityDescriptor` |
| FR-PIPE-08 | Dial retry with exponential backoff + jitter when `RetryConfig` is set (default attempts cover a peer that is still starting); retryable vs non-retryable classes defined. | Should | `RetryConfig` |
| FR-PIPE-09 | Optional circuit breaker on dial (reusing `core/circuitbreaker`) opens after a failure threshold and short-circuits with `ErrCircuitOpen`. | Should | `BreakerConfig` |
| FR-PIPE-10 | Client-side connection pooling (reusing `core/pool/resourcepool`) enabled by a non-zero `PoolConfig`; zero value disables pooling (default off); `DefaultPoolConfig()` gives one-line opt-in. | Should | `PoolConfig`, `DefaultPoolConfig`, `Client.Stats` |
| FR-PIPE-11 | `Close` on `Conn`/`Client`/`Listener` drains gracefully within a context deadline and is idempotent; `Listener.Close` unlinks the Unix socket file. | Must | `Conn.Close`, `Client.Close`, `Listener.Close` |
| FR-PIPE-12 | All failure modes surface as sentinel errors matchable with `errors.Is`, re-exported at package root. | Must | `ErrFrameTooLarge`, `ErrPeerUnauthorized`, `ErrEndpointInUse`, … |
| FR-PIPE-13 | Dial and accept emit OTel spans; frame/byte/connection/peer-auth counters + duration histograms emit via the `motadatagosdk/otel` facade. `Send`/`Recv` are metrics-only (no per-frame spans). | Must | (observability, see §8) |
| FR-PIPE-14 | The backend is the build-selected OS adapter by default; `Config.BackendFactory` injects an alternative (e.g. in-memory `net.Pipe`) for tests, with no global registry and no `init()`. | Must | `Backend`, `BackendFactory`, `Config.BackendFactory` |
| FR-PIPE-15 | On Windows, byte-mode is the default; `MessageMode` opts into named-pipe message framing. The SDK length-prefix framing is authoritative regardless, so wire behavior is identical across OSes. | Should | `Config.MessageMode`, `ServerConfig.MessageMode` |

<!-- Each FR-id is referenced from §Skills-Manifest "Why required" and from generated code via [traces-to: TPRD-§4-FR-<id>]. -->

## §5 Non-Functional Requirements

### Performance Targets
Loopback (client↔server in one process), **4 KiB frames**, established connection unless noted. Targets are **OS-tiered**, each seeded from `-count=12` median distributions over the full operation surface — per-symbol one-directional `Send`/`Recv`, `Connect` (dial+accept+close cycle), and 4 KiB round-trip — on two hosts: **Unix tier** = Host A loopback UDS (i7-1185G7 bare-metal, go1.26.3); **Windows tier** = Host B go-winio named pipe (2× EPYC 7C13 VM, go1.26.4). Full matrix + device specs + reproduce: `runs/pipe-transport-backend-decision.md`. **Hardware-confound caveat (§6):** the two hosts differ, so the cross-OS ratio is not used; each tier is gated only against its own OS. Targets are a margin over the measured median; the perf architect refines at D1 into `design/perf-budget.md`.

- **Latency — `Conn.Send`** (4 KiB) — **Unix**: p50 ≤ 3 µs, p95 ≤ 6 µs, p99 ≤ 12 µs (measured median **1.66 µs**). **Windows**: p50 ≤ 15 µs, p95 ≤ 30 µs, p99 ≤ 60 µs (measured median **8.2 µs**).
- **Latency — `Conn.Recv`** (4 KiB) — **Unix**: p50 ≤ 3 µs, p95 ≤ 6 µs, p99 ≤ 12 µs (median **1.69 µs**). **Windows**: p50 ≤ 15 µs, p95 ≤ 30 µs, p99 ≤ 60 µs (median **8.1 µs**).
- **Latency — `Client.Connect`** (cold dial+accept) — **Unix**: p50 ≤ 20 µs, p95 ≤ 50 µs (median **10.4 µs**). **Windows**: p50 ≤ 15 ms, p95 ≤ 30 ms (measured median **10.0 ms** — named-pipe open is ~1000× the UDS cost; see ⚠ below). Pooled/persistent-reuse path (both): p50 ≤ 5 µs Unix / ≤ 15 µs Windows.
- **Throughput** (single connection, 4 KiB, one-directional `Send`) — **Unix**: ≥ 400,000 frames/sec (median 1.66 µs/op → ~602k/s). **Windows**: ≥ 80,000 frames/sec (median 8.2 µs/op → ~122k/s).
- **Allocation budget** (G104 enforced at M3.5) — **Unix**: `Conn.Send` ≤ 1 alloc/op; `Conn.Recv` ≤ 2 allocs/op (measured **0**, all sizes). **Windows**: `Conn.Send`/`Conn.Recv` ≤ 6 allocs/op, ≤ 512 B/op (measured **3–4 allocs / 320 B** — go-winio IOCP-wrapper floor, payload-independent at small sizes).

> ⚠ **Windows connection-setup is the dominant cost (architectural):** cold named-pipe `Connect` measured **~10 ms** (vs ~10 µs UDS — ~1000×). Windows callers **MUST reuse connections** — enable `PoolConfig` or hold a long-lived `Conn` — and never connect-per-message. The framed transport has no request/response boundary, so a held connection is the intended pattern. This makes §9 pooling effectively mandatory on Windows; it stays opt-in by config (default off remains correct for Unix, where `Connect` is ~10 µs). Pooled/persistent reuse removes the 10 ms from the steady-state path.
- **Complexity** (G107 scaling sweep at T5): `Send`/`Recv` O(n) in payload bytes; `Client.Connect` (pooled) O(1) amortized; `Listener.Accept` O(1).
- **Oracle margin** (G108): `Send`/`Recv` p50 ≤ 1.3× a raw `net.Conn` + `bufio` length-prefix reference implementation.
- **MMD (soak)** (G105): minimum 30 min soak for connection-leak and latency-drift symbols (`Connect`/`Close` churn, long-lived `Send`/`Recv`).

### Drift Signals
- Rising p99 `Send`/`Recv` latency at fixed throughput → buffer/GC pressure regression.
- Growing `connections.active` gauge under steady offered load → connection / goroutine / socket-fd leak.
- Falling pooled-`Connect` hit ratio → pool sizing/eviction regression.
- Rising `peer.auth.failures` rate → ACL/credential-mapping regression or hostile local caller.

Consumed by the perf architect at D1 to author `design/perf-budget.md`.

## §6 Dependencies + Config Validation

**Backend decision (benchmarked):** Unix backend is **stdlib `net` Unix domain socket (`SOCK_STREAM`)** — zero new dependency. Windows backend is **`github.com/Microsoft/go-winio`**, the only maintained library exposing Windows named pipes as `net.Conn`/`net.Listener` (IOCP-backed); it is **MIT-licensed and already present in `go.mod` as an indirect dependency** (`v0.6.2`, pulled by testcontainers/docker), so promoting it to direct adds **zero** modules to the graph. UDS is chosen over FIFO/`os.Pipe` because it is bidirectional, connection-oriented, and carries peer credentials, mapping 1:1 to the Windows named-pipe model. Full evidence + measured tables + claim-validation + reproduce steps: `runs/pipe-transport-backend-decision.md`.

**Benchmark provenance + hardware confound (for §5 perf targets):** the §5 numbers come from `-count=12` median distributions on two **different** machines — Unix tier on **Host A** (Dell Latitude 5420 bare-metal, Intel i7-1185G7 4C/8T, 30 GiB, Linux 6.17, go1.26.3); Windows tier on **Host B** (VMware VM, 2× AMD EPYC 7C13 / 16 vCPU, 24 GB, Windows Server 2022 b20348, go1.26.4). Because the hosts differ in CPU/vendor/virtualization, the **cross-OS ratio is confounded and is NOT used to set any target**; each OS-tier is gated only against benches on its own OS (where the confound does not apply). A same-hardware cross-OS A/B (dual-boot or equal VMs) is deferred to Phase 3 T5 and is the only basis on which a cross-OS performance claim may be made. The Windows-structural findings that hold regardless of hardware — go-winio's irreducible ~8 alloc/op + 640 B/op IOCP floor, and syscall-bound small-frame latency — are what the Windows §5 tier is anchored to.

- `net`, `os`, `syscall`/`golang.org/x/sys/unix` (Unix `SO_PEERCRED`) — Go 1.26 stdlib + `x/sys`; license: BSD-3-Clause; vuln-scan: covered by `govulncheck`; lockfile-scan: `osv-scanner`; transitive count: 0 (stdlib) / minimal (`x/sys`); last-commit age: toolchain-pinned. (`golang.org/x/sys` is already in `go.mod` via existing deps; confirm at dep-vet.)
- `github.com/Microsoft/go-winio@v0.6.2` (Windows only, build-tagged) — license: **MIT**; vuln-scan: `govulncheck` clean; lockfile-scan: `osv-scanner`; transitive count: low (golang.org/x/sys); last-commit age: released 2024-04 (stable, Microsoft-maintained); **already indirect in `go.mod`** → promote to direct, no graph growth. Dep-Vet Devil verdict required (license MIT ∈ allowlist).
- `motadatagosdk/core/pool/resourcepool` (in-tree) — connection pooling.
- `motadatagosdk/core/circuitbreaker` (in-tree, wraps `github.com/sony/gobreaker/v2` already in `go.mod`) — dial breaker.
- `motadatagosdk/otel` + `motadatagosdk/otel/tracer|metrics|logger` (in-tree) — observability facade.

Config validation rules:
- Fail fast (`ErrInvalidConfig`) if both `Name` and `Address` are empty, or if both are set and disagree.
- Reject `MaxFrameSize <= 0`; apply a documented default (16 MiB) when unset.
- On Unix, reject a `SocketMode` wider than `0o777`; warn (single WARN log) when `SocketMode` grants group/other write (`& 0o022 != 0`) — broadens the local attack surface.
- On Windows, an empty `SecurityDescriptor` applies go-winio's default pipe ACL (current user + SYSTEM); a malformed SDDL fails fast with `ErrInvalidConfig`.
- Reject a `Config.Name` containing path separators or `..` (endpoint-name injection guard); the `Endpoint` helper owns path construction.
- `RetryConfig`/`BreakerConfig`/`PoolConfig` zero values disable their feature (opt-in).

## §7 Config + API

```go
// Package pipe provides a connection-oriented, framed, same-host inter-process
// byte transport. On Unix it uses a stdlib net Unix domain socket; on Windows it
// uses a Microsoft/go-winio named pipe. The public surface references no
// OS-specific type, so consumer code is identical across operating systems and
// the underlying primitive can be swapped via an SDK update with no consumer change.
package pipe

import (
	"context"
	"net"
	"time"

	"motadatagosdk/otel/tracer"
)

// ── Endpoint addressing ──────────────────────────────────────────────────────

// Endpoint resolves an OS-neutral endpoint name to the platform-correct address:
// on Unix a pathname socket under the configured directory (default /run/motadata),
// on Windows a \\.\pipe\<name> path. Names with path separators or ".." are rejected.
func Endpoint(name string) (string, error)

// ── Peer authentication ──────────────────────────────────────────────────────

// PeerCredentials reports the OS identity of the connected peer process, the
// local-IPC analog of a verified TLS peer certificate. Fields are populated
// best-effort per platform; Unsupported reports when the OS cannot supply them.
type PeerCredentials struct {
	UID         uint32 // UID is the peer process user id (Unix; 0 on Windows).
	GID         uint32 // GID is the peer process group id (Unix; 0 on Windows).
	PID         int32  // PID is the peer process id (both platforms, best-effort).
	UserSID     string // UserSID is the peer process token user SID (Windows; empty on Unix).
	Unsupported bool   // Unsupported is true if the platform could not supply credentials.
}

// Authorizer decides whether an accepted peer may proceed. Returning a non-nil
// error rejects the connection before its first frame; the server surfaces
// ErrPeerUnauthorized to the rejected peer and increments peer.auth.failures.
type Authorizer func(ctx context.Context, creds PeerCredentials) error

// ── Client / server configuration ───────────────────────────────────────────

// Config configures a dialing client.
type Config struct {
	Name              string         // Name is the OS-neutral endpoint name; resolved via Endpoint. One of Name/Address required.
	Address           string         // Address is a raw OS endpoint (socket path or \\.\pipe\name) overriding Name.
	DialTimeout       time.Duration  // DialTimeout bounds one dial attempt (default 10s).
	MaxFrameSize      int            // MaxFrameSize caps an inbound frame in bytes (default 16 MiB).
	MessageMode       bool           // MessageMode selects Windows named-pipe message mode; ignored on Unix. SDK framing is authoritative regardless.
	Pool              PoolConfig     // Pool configures connection pooling; zero value disables it.
	Retry             RetryConfig    // Retry configures dial retry; zero value disables it.
	Breaker           BreakerConfig  // Breaker configures a dial circuit breaker; zero value disables it.
	BackendFactory    BackendFactory // BackendFactory, if set, overrides the build-selected OS adapter (e.g. in-memory net.Pipe for tests).
	ObservabilityName string         // ObservabilityName is the low-cardinality component name for spans/metrics.
	TracerProvider    tracer.Provider // TracerProvider opts in a specific provider; nil uses the SDK facade global.
}

// ServerConfig configures a listening server.
type ServerConfig struct {
	Name               string         // Name is the OS-neutral endpoint name; resolved via Endpoint. One of Name/Address required.
	Address            string         // Address is a raw OS endpoint overriding Name.
	MaxFrameSize       int            // MaxFrameSize caps an inbound frame in bytes (default 16 MiB).
	MessageMode        bool           // MessageMode selects Windows named-pipe message mode; ignored on Unix.
	SocketMode         uint32         // SocketMode is the Unix socket file mode (default 0o600); ignored on Windows.
	SecurityDescriptor string         // SecurityDescriptor is the Windows pipe SDDL ACL; empty uses the go-winio default. Ignored on Unix.
	Authorize          Authorizer     // Authorize, if set, accepts/rejects each peer by credentials before its first frame.
	BackendFactory     BackendFactory // BackendFactory injects an alternative adapter (tests).
	ObservabilityName  string
	TracerProvider     tracer.Provider
}

// PoolConfig configures client-side connection pooling over core/pool/resourcepool.
// A zero MaxSize disables pooling.
type PoolConfig struct {
	MinSize     int           // MinSize is the number of warm connections kept ready.
	MaxSize     int           // MaxSize caps total pooled connections; 0 disables pooling.
	IdleTimeout time.Duration // IdleTimeout evicts connections idle longer than this.
	AcquireWait time.Duration // AcquireWait bounds the wait for a free connection before ErrPoolExhausted.
}

// RetryConfig configures dial retry with exponential backoff and jitter, for the
// common case of dialing a peer that is still starting up.
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

// ── Backend seam (advanced / tests) ──────────────────────────────────────────

// Backend is the driven port implemented by the per-OS adapter. The build-selected
// adapter (Unix domain socket on Unix, go-winio named pipe on Windows) is compiled
// in and used when BackendFactory is nil. The package keeps no global registry and
// defines no init().
type Backend interface {
	// DialConn establishes a raw connection for the client role.
	DialConn(ctx context.Context, address string, cfg Config) (net.Conn, error)
	// ListenConn binds a listener for the server role.
	ListenConn(ctx context.Context, address string, cfg ServerConfig) (net.Listener, error)
	// Credentials extracts peer credentials from an accepted raw connection.
	Credentials(c net.Conn) (PeerCredentials, error)
}

// BackendFactory constructs a Backend. Injecting a factory swaps the transport
// implementation with no change to the Config/Conn/Client/Listener contract.
type BackendFactory func() (Backend, error)

// ── Stable ports ─────────────────────────────────────────────────────────────

// Conn is a framed, full-duplex local-IPC connection. All methods take a context
// first and honor its deadline and cancellation.
type Conn interface {
	// Send writes payload as one length-prefixed frame.
	Send(ctx context.Context, payload []byte) error
	// Recv reads the next full frame, returning ErrFrameTooLarge if it exceeds MaxFrameSize.
	Recv(ctx context.Context) ([]byte, error)
	// PeerCredentials reports the connected peer's OS identity.
	PeerCredentials() PeerCredentials
	// RemoteAddr returns the peer address.
	RemoteAddr() net.Addr
	// LocalAddr returns the local address.
	LocalAddr() net.Addr
	// Close releases the connection, returning it to the pool if pooled. Idempotent.
	Close(ctx context.Context) error
}

// Client dials connections to the configured endpoint.
type Client interface {
	// Connect returns a ready framed Conn, drawn from the pool if pooling is enabled.
	Connect(ctx context.Context) (Conn, error)
	// Close drains the pool and releases client resources. Idempotent.
	Close(ctx context.Context) error
	// Stats returns transport and pool counters.
	Stats() Stats
}

// Listener accepts inbound connections on the configured endpoint.
type Listener interface {
	// Accept returns the next inbound Conn after peer authorization (if configured).
	Accept(ctx context.Context) (Conn, error)
	// Addr returns the bound local endpoint address.
	Addr() net.Addr
	// Close stops accepting, unlinks the Unix socket file, and releases the listener. Idempotent.
	Close(ctx context.Context) error
}

// Stats reports point-in-time transport counters.
type Stats struct {
	ActiveConns int64 // ActiveConns is the count of currently open connections.
	PoolIdle    int64 // PoolIdle is the count of idle pooled connections.
	DialTotal   int64 // DialTotal is the cumulative dial count.
	DialErrors  int64 // DialErrors is the cumulative failed-dial count.
	AuthErrors  int64 // AuthErrors is the cumulative peer-authorization rejection count.
}

// ── Constructors ─────────────────────────────────────────────────────────────

// Dial validates cfg, resolves the endpoint + backend, and returns a Client. It
// does not open a connection until Client.Connect is called (unless Pool.MinSize > 0).
func Dial(ctx context.Context, cfg Config) (Client, error)

// Listen validates cfg, resolves the endpoint + backend, binds it (reclaiming a
// stale Unix socket file if present), and returns a Listener.
func Listen(ctx context.Context, cfg ServerConfig) (Listener, error)

// DefaultPoolConfig returns a PoolConfig with production-sane pooling defaults,
// for one-line opt-in: Config{Pool: DefaultPoolConfig()}.
func DefaultPoolConfig() PoolConfig

// ── Sentinel errors (errors.Is) ──────────────────────────────────────────────

var (
	ErrNotConnected     error // ErrNotConnected indicates an operation on a connection that is not established.
	ErrInvalidConfig    error // ErrInvalidConfig indicates a malformed Config/ServerConfig.
	ErrFrameTooLarge    error // ErrFrameTooLarge indicates an inbound frame exceeded MaxFrameSize.
	ErrConnClosed       error // ErrConnClosed indicates use of a closed connection.
	ErrDialTimeout      error // ErrDialTimeout indicates a dial attempt exceeded DialTimeout.
	ErrEndpointInUse    error // ErrEndpointInUse indicates the endpoint is already bound by a live listener.
	ErrEndpointNotFound error // ErrEndpointNotFound indicates no listener is bound at the endpoint (peer not up).
	ErrPeerUnauthorized error // ErrPeerUnauthorized indicates the Authorizer rejected the peer's credentials.
	ErrPoolExhausted    error // ErrPoolExhausted indicates no pooled connection became available within AcquireWait.
	ErrCircuitOpen      error // ErrCircuitOpen indicates the dial circuit breaker is open.
	ErrUnsupported      error // ErrUnsupported indicates a feature unavailable on the current platform.
)
```

<!-- Generated symbols will be stamped with [traces-to: TPRD-§7-<id>] (G99/G102/G103). Do not author markers by hand. -->

## §8 Observability

### Spans
| Span name | Attributes |
|---|---|
| `motadata.pipe.dial` | `pipe.endpoint`, `pipe.os` (unix/windows), `outcome` |
| `motadata.pipe.accept` | `pipe.endpoint`, `pipe.os`, `peer.authorized`, `outcome` |

`Send`/`Recv` are intentionally metrics-only (per-frame spans would be high-volume); span names are static and low-cardinality. `pipe.endpoint` is the logical `Name`, never a per-connection path, to bound cardinality.

### Metrics
| Metric | Type | Unit | Labels |
|---|---|---|---|
| `motadata.pipe.connections.active` | gauge | `{connections}` | `role` (client/server), `pipe.os` |
| `motadata.pipe.dial.duration` | histogram | `ms` | `outcome` |
| `motadata.pipe.frames.sent` | counter | `{frames}` | `role` |
| `motadata.pipe.frames.received` | counter | `{frames}` | `role` |
| `motadata.pipe.bytes.sent` | counter | `By` | `role` |
| `motadata.pipe.bytes.received` | counter | `By` | `role` |
| `motadata.pipe.pool.acquire.duration` | histogram | `ms` | `outcome` |
| `motadata.pipe.peer.auth.failures` | counter | `{rejections}` | `role` |
| `motadata.pipe.errors` | counter | `{errors}` | `kind` (frame/dial/auth/pool) |

Trace propagation strategy: via the `motadatagosdk/otel` facade (`tracer.Start`); never the raw upstream OTel SDK. The transport carries opaque bytes and does **not** inject/extract trace headers into the frame stream (that is the consumer protocol's concern). No credential value (UID/GID/SID) is ever emitted as a span attribute or metric label (G38).

## §9 Resilience
- **Retry** (dial only): `RetryConfig` exponential backoff + jitter. Retryable: `ErrEndpointNotFound` (peer not yet listening), connection-refused, timeout. Non-retryable: `ErrInvalidConfig`, `ErrPeerUnauthorized`, context cancellation, `ErrUnsupported`.
- **Circuit breaker** (dial only, via `core/circuitbreaker`): opens after `FailureThreshold` failures within `Window`; stays open for `RecoveryTimeout`; allows `HalfOpenMax` probes; open state short-circuits with `ErrCircuitOpen`.
- **Connection pool** (client, via `core/pool/resourcepool`): min `PoolConfig.MinSize`, max `MaxSize`, idle eviction `IdleTimeout`; acquisition blocks up to `AcquireWait` then returns `ErrPoolExhausted`; broken connections are destroyed on return and lazily recreated. Default off (see §14 OQ-005). **On Windows, pooling/persistent-connection is effectively mandatory** — a cold named-pipe `Connect` measured **~10 ms** (§5 ⚠), so connect-per-message is a non-starter; callers either set `PoolConfig` or hold a long-lived `Conn`. On Unix `Connect` is ~10 µs, so default-off is fine.
- **Stale endpoint reclaim** (Unix): `Listen` removes a leftover socket file whose listener is dead (connect probe fails) and rebinds; a live listener yields `ErrEndpointInUse`.

## §10 Security
- **Transport security model**: same-host, kernel-mediated; **no TLS** (Non-Goal §2). Confidentiality + integrity rest on (a) endpoint ACLs and (b) peer-credential authentication.
- **Endpoint ACL**: Unix — socket file mode `SocketMode` (default `0o600`, owner-only) plus restrictive parent-dir perms; abstract-namespace sockets are **not** used by default (they bypass filesystem perms). Windows — pipe `SecurityDescriptor` (SDDL); empty defaults to current-user + SYSTEM via go-winio.
- **Peer authentication**: `Conn.PeerCredentials` (Unix `SO_PEERCRED`; Windows client process id + token user SID); optional `Authorizer` rejects unauthorized peers before the first frame with `ErrPeerUnauthorized`. This is the local-IPC analog of mTLS peer-cert verification.
- **Credential provider**: n/a (no cryptographic credentials); never plaintext secrets in source (G69). Integration tests read no embedded secrets.
- **Input validation**: `MaxFrameSize` bounds inbound frames (DoS guard, fuzz-tested); length prefix validated before allocation; endpoint `Name` rejected if it contains path separators or `..` (path-injection guard); `SocketMode` group/other-write emits a WARN.

## §11 Testing
- **Unit**: table-driven cases per public method (`Dial`, `Listen`, `Connect`, `Accept`, `Send`, `Recv`, `Close`, `PeerCredentials`, config-validation matrix); coverage ≥ 90% on the new package (G60). Hermetic via the in-memory `net.Pipe` `BackendFactory` seam (no real sockets needed for logic tests).
- **Integration**: real client↔server over a real Unix domain socket on Unix CI and a real named pipe on **`windows-latest`** CI (build-tagged); peer-auth accept/reject paths exercised with a spawned child process of a different uid (Unix) where the runner permits; stale-socket-reclaim path; image/runner versions pinned.
- **Benchmarks**: per hot-path symbol (`Send`, `Recv`, pooled `Connect`); allocation reporting on (G104); benchstat regression compare vs baseline (G65); paired `[constraint:]` benches for the §5 targets. Baseline numbers seeded from `runs/pipe-transport-backend-decision.md`.
- **Fuzz**: frame parser / length-prefix decoder with crash-triage (malformed prefixes, truncated frames, oversize claims).
- **Leak**: `goleak` harness clean across dial/accept/close cycles (G63); no goroutine, fd, or socket-file leak after `Close`.
- **Flake hunt**: `-count=N` on the integration suite; flake hunter at T3 (accept/connect races, pool races, Windows pipe-busy retries).

## §12 Breaking-Change Risk

**Mode A: no breaking changes (new exports only).** The package `motadatagosdk/transport/pipe` is additive; no existing exported symbol is changed or removed. Promoting `github.com/Microsoft/go-winio` from indirect to direct in `go.mod` changes no public API and no existing build (it is already in the module graph). Semver implication: **MINOR**. Each new exported symbol pairs with a `[stable-since: vX.Y.Z]` decision (G101) at first release. Agrees with §1.

## §13 Rollout
- **H1 (TPRD approval)**: TPRD complete, manifests resolve, `§Target-Language: go` resolves to a pack manifest, all §14 blockers resolved.
- **H5 (design)**: API stub passes design devils (semver, convention, security, over-engineering, dep-vet — including the go-winio promotion); `design/perf-budget.md` authored from §5; the cross-platform backend seam reviewed for the zero-OS-type-leak invariant.
- **H7 (impl)**: code passes impl devils + leak/marker/constraint scans, ≥ 90% coverage, zero `TODO`/`ErrNotImplemented`, every §7 symbol has impl + test + doc-comment + (hot-path) bench + runnable `Example_*`; both `unix` and `windows` build tags compile clean.
- **H9 (testing)**: perf-confidence gates pass — regression, oracle, allocation, complexity, drift, MMD soak; Unix + Windows integration green.
- **H10 (merge)**: final diff reviewed; learning-notifications acknowledged; merge recommendation on `sdk-pipeline/<run-id>`.

## §14 Open Questions / Pre-Phase-1 Clarifications
- **OQ-001 [RESOLVED]**: Base branch for the pipeline's `sdk-pipeline/<run-id>` working branch. — **ANSWER**: `origin/NATS_Updated` (confirmed present after `git fetch`; current checkout is `NATS_Updated`). **Blocker**: NO (resolved).
- **OQ-002 [RESOLVED]**: Is OTel required for this transport, and at what granularity? — **ANSWER**: **Yes, required** (per SDK-wide rule "OTel required, language-native"). Wired via the `motadatagosdk/otel` facade only. Granularity is **tiered**: lifecycle spans on `Dial`/`Accept` + aggregate counters/histograms for frames/bytes/connections/peer-auth/errors; **`Send`/`Recv` are metrics-only — no per-frame spans** (per-frame spans on a high-throughput local channel would choke the trace pipeline, matching `transport/rawdatagram` and `transport/tcptls`). **Blocker**: NO.
- **OQ-003 [RESOLVED]**: Which library backs the Windows named-pipe path, and does it add a dependency? — **ANSWER**: `github.com/Microsoft/go-winio@v0.6.2` (MIT, IOCP-backed, `net.Conn`/`net.Listener` parity). It is **already an indirect dependency** in `go.mod`, so promoting it to direct adds **no** new module. Unix uses stdlib `net` (zero dep). Evidence + benchmark: `runs/pipe-transport-backend-decision.md`. **Blocker**: NO.
- **OQ-004 [RESOLVED]**: Linux IPC primitive — Unix domain socket or FIFO/`os.Pipe`? — **ANSWER**: **Unix domain socket (`SOCK_STREAM`)**. Bidirectional, connection-oriented, carries peer credentials, maps 1:1 to the Windows named-pipe model → one API both OSes. FIFO is unidirectional + peer-auth-less and was measured only marginally faster for sub-1 KB messages (and slower for ≥1 MB) — not worth an API split. See backend-decision §1–§3. **Blocker**: NO.
- **OQ-005 [RESOLVED]**: Client connection pooling default. — **ANSWER**: **Opt-in / default off** — a zero `PoolConfig` disables pooling; `DefaultPoolConfig()` gives one-line opt-in. Rationale: the framed transport has no request/response boundary, so default-on would expose a stale-frame cross-talk hazard; opt-in confines that edge to deliberate users. **Caveat from benchmark (count=12):** Windows cold `Connect` ≈ **10 ms** (vs ~10 µs Unix), so Windows callers are documented to opt into pooling or hold a persistent `Conn` (§5 ⚠, §9); the default stays off because Unix `Connect` is cheap and default-on carries the cross-talk hazard. **Blocker**: NO.

<!-- Any OQ with Blocker: YES that is unresolved at preflight → exit 4. Cap of 5 clarifying questions in Wave I4. -->

## §Skills-Manifest
| Skill | Min version | Why required |
|---|---|---|
| go-struct-interface-design | 1.0.0 | §7 ports (Conn/Client/Listener) |
| go-sdk-config-struct-pattern | 1.0.0 | §7 Config/ServerConfig + constructors |
| go-hexagonal-architecture | 1.0.0 | FR-PIPE-14 (per-OS backend seam + net.Pipe test adapter) |
| go-module-paths | 1.0.0 | package path `transport/pipe` |
| go-context-deadline-patterns | 1.0.0 | FR-PIPE-05 (ctx-first I/O) |
| go-client-shutdown-lifecycle | 1.0.0 | FR-PIPE-11 (graceful idempotent Close + socket unlink) |
| go-connection-pool-tuning | 1.0.0 | FR-PIPE-10, §9 pool |
| go-circuit-breaker-policy | 1.0.0 | FR-PIPE-09, §9 breaker |
| go-idempotent-retry-patterns | 1.0.0 | FR-PIPE-08, §9 retry |
| go-backpressure-flow-control | 1.0.0 | §5 throughput, framed Send/Recv |
| go-error-handling-patterns | 1.0.0 | FR-PIPE-12 (sentinels) |
| go-otel-instrumentation | 1.0.0 | FR-PIPE-13, §8 |
| go-sdk-otel-hook-integration | 1.0.0 | §8 facade provider opt-in |
| go-table-driven-tests | 1.0.0 | §11 unit |
| go-tdd-patterns | 1.0.0 | §11 red/green/refactor |
| go-fuzz-patterns | 1.0.0 | §11 frame-parser fuzz |
| go-testcontainers-setup | 1.0.0 | §11 integration harness |
| goroutine-leak-prevention | 1.0.0 | §11 leak (G63) |
| go-client-mock-strategy | 1.0.0 | §11 net.Pipe backend-seam mocks |
| go-example-function-patterns | 1.0.0 | runnable `Example_*` per symbol |
| go-cross-platform-build-tags | 1.0.0 | FR-PIPE-03 (unix/windows adapter split) — **WARN expected (skill not yet in skill-index; auto-files to docs/PROPOSED-SKILLS.md)** |
| go-named-pipe-winio | 1.0.0 | FR-PIPE-03 (go-winio ListenPipe/DialPipeContext/PipeConfig) — **WARN expected** |
| go-peer-credential-auth | 1.0.0 | FR-PIPE-06 (SO_PEERCRED / named-pipe client identity) — **WARN expected** |
| go-unix-socket-patterns | 1.0.0 | FR-PIPE-02/07 (UDS bind, mode, stale-socket reclaim) — **WARN expected** |

<!-- G23 (WARN-only): each skill must exist in skills/skill-index.json at version ≥ declared. Misses auto-file to docs/PROPOSED-SKILLS.md with run-id + reason. The four WARN-expected skills above do not block intake; their sections implement from in-pipeline general patterns (go-hexagonal-architecture, go-struct-interface-design, go-error-handling-patterns) plus this TPRD's explicit prescriptions. -->

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
  - src/motadatagosdk/transport/pipe/
skip: false
examples_allowed: false

## §Versioning
bump: MINOR
reasoning: "Adds new public package motadatagosdk/transport/pipe with new exported symbols only; promotes github.com/Microsoft/go-winio from indirect to direct (already in the module graph). Removes or renames nothing."
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
  - peer.uid
  - peer.gid
  - peer.user_sid

### Declared identifiers
- declared_metric_ids:
  - motadata.pipe.connections.active
  - motadata.pipe.dial.duration
  - motadata.pipe.frames.sent
  - motadata.pipe.frames.received
  - motadata.pipe.bytes.sent
  - motadata.pipe.bytes.received
  - motadata.pipe.pool.acquire.duration
  - motadata.pipe.peer.auth.failures
  - motadata.pipe.errors
- declared_span_names:
  - motadata.pipe.dial
  - motadata.pipe.accept

### Logging
- log_correlation: required

### Surface
- nats_surface: no

### Tenant attribution
- tenant_attribution: none
