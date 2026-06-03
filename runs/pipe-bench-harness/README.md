# Pipe-transport benchmark harness

Reproduces the numbers in `../pipe-transport-backend-decision.md` and the §5 targets in
`../pipe-transport-tprd.md`. Round-trip = echo request-reply; `Send`/`Recv` = one-directional
stream; `Connect` = dial+accept+close cycle. All `-count=12`, medians reported.

## Linux / Unix (UDS, TCP-loopback, FIFO)

```sh
cd linux
go test -bench=. -benchmem -benchtime=1s -count=12 -run=^$
```

No external dependency (stdlib `net`, `syscall.Mkfifo`).

## Windows (go-winio named pipe)

```sh
cd windows
go test -bench=. -benchmem -benchtime=1s -count=12 -run=^$
```

Requires `github.com/Microsoft/go-winio v0.6.2`. On an air-gapped box, vendor it on a connected
host (`go mod vendor`), copy the tree over, and run with `-mod=vendor`.

## Hosts used

- **Host A (Unix):** Dell Latitude 5420, Intel i7-1185G7 (4C/8T), 30 GiB, Linux 6.17.0-29, `go1.26.3`.
- **Host B (Windows):** VMware VM, 2× AMD EPYC 7C13 (16 vCPU), 24 GB, Windows Server 2022 b20348, `go1.26.4`.

Hosts differ — per-OS distributions are valid; the cross-OS ratio is confounded (see decision doc §6).
