package winpipebench

import (
	"net"
	"sync"
	"testing"

	winio "github.com/Microsoft/go-winio"
)

// roundTrip: client writes payload, server echoes it back. Measures
// request-reply latency over a Windows named pipe (go-winio, IOCP-backed).
// Mirrors the Linux UDS/TCP/FIFO harness in /tmp/pipebench for comparability.
func benchPipeRoundTrip(b *testing.B, size int) {
	const path = `\\.\pipe\motadata-bench`
	ln, err := winio.ListenPipe(path, &winio.PipeConfig{
		InputBufferSize:  65536,
		OutputBufferSize: 65536,
	})
	if err != nil {
		b.Fatal(err)
	}
	defer ln.Close()

	type res struct {
		c   net.Conn
		err error
	}
	ch := make(chan res, 1)
	go func() {
		c, err := ln.Accept()
		ch <- res{c, err}
	}()

	client, err := winio.DialPipe(path, nil)
	if err != nil {
		b.Fatal(err)
	}
	srv := <-ch
	if srv.err != nil {
		b.Fatal(srv.err)
	}
	defer client.Close()
	defer srv.c.Close()

	payload := make([]byte, size)
	echo := make([]byte, size)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		buf := make([]byte, size)
		for i := 0; i < b.N; i++ {
			if _, err := readFull(srv.c, buf); err != nil {
				return
			}
			if _, err := srv.c.Write(buf); err != nil {
				return
			}
		}
	}()

	b.SetBytes(int64(size))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := client.Write(payload); err != nil {
			b.Fatal(err)
		}
		if _, err := readFull(client, echo); err != nil {
			b.Fatal(err)
		}
	}
	b.StopTimer()
	client.Close()
	wg.Wait()
}

func readFull(c net.Conn, buf []byte) (int, error) {
	got := 0
	for got < len(buf) {
		n, err := c.Read(buf[got:])
		if err != nil {
			return got, err
		}
		got += n
	}
	return got, nil
}

func BenchmarkNamedPipe_64B(b *testing.B)  { benchPipeRoundTrip(b, 64) }
func BenchmarkNamedPipe_1KB(b *testing.B)  { benchPipeRoundTrip(b, 1024) }
func BenchmarkNamedPipe_64KB(b *testing.B) { benchPipeRoundTrip(b, 64*1024) }
func BenchmarkNamedPipe_1MB(b *testing.B)  { benchPipeRoundTrip(b, 1024*1024) }
