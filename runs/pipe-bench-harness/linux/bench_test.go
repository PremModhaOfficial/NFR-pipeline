package pipebench

import (
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

// roundTrip: client writes payload, server echoes it back. Measures
// request-reply latency over the given net.Conn pair.
func benchConnRoundTrip(b *testing.B, c1, c2 net.Conn, size int) {
	payload := make([]byte, size)
	echo := make([]byte, size)
	var wg sync.WaitGroup
	wg.Add(1)
	// echo server on c2
	go func() {
		defer wg.Done()
		buf := make([]byte, size)
		for i := 0; i < b.N; i++ {
			if _, err := readFull(c2, buf); err != nil {
				return
			}
			if _, err := c2.Write(buf); err != nil {
				return
			}
		}
	}()
	b.SetBytes(int64(size))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := c1.Write(payload); err != nil {
			b.Fatal(err)
		}
		if _, err := readFull(c1, echo); err != nil {
			b.Fatal(err)
		}
	}
	b.StopTimer()
	c1.Close()
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

// --- Unix domain socket (SOCK_STREAM) ---
func benchUDS(b *testing.B, size int) {
	dir := b.TempDir()
	sock := filepath.Join(dir, "s.sock")
	ln, err := net.Listen("unix", sock)
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
	client, err := net.Dial("unix", sock)
	if err != nil {
		b.Fatal(err)
	}
	srv := <-ch
	if srv.err != nil {
		b.Fatal(srv.err)
	}
	defer client.Close()
	defer srv.c.Close()
	benchConnRoundTrip(b, client, srv.c, size)
}

func BenchmarkUDS_64B(b *testing.B)  { benchUDS(b, 64) }
func BenchmarkUDS_1KB(b *testing.B)  { benchUDS(b, 1024) }
func BenchmarkUDS_64KB(b *testing.B) { benchUDS(b, 64*1024) }
func BenchmarkUDS_1MB(b *testing.B)  { benchUDS(b, 1024*1024) }

// --- TCP loopback (baseline comparison) ---
func benchTCP(b *testing.B, size int) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
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
	client, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		b.Fatal(err)
	}
	srv := <-ch
	if srv.err != nil {
		b.Fatal(srv.err)
	}
	if tc, ok := client.(*net.TCPConn); ok {
		tc.SetNoDelay(true)
	}
	defer client.Close()
	defer srv.c.Close()
	benchConnRoundTrip(b, client, srv.c, size)
}

func BenchmarkTCP_64B(b *testing.B)  { benchTCP(b, 64) }
func BenchmarkTCP_1KB(b *testing.B)  { benchTCP(b, 1024) }
func BenchmarkTCP_64KB(b *testing.B) { benchTCP(b, 64*1024) }
func BenchmarkTCP_1MB(b *testing.B)  { benchTCP(b, 1024*1024) }

// --- FIFO (named pipe) one-way throughput; two FIFOs for round trip ---
func benchFIFO(b *testing.B, size int) {
	dir := b.TempDir()
	reqPath := filepath.Join(dir, "req")
	respPath := filepath.Join(dir, "resp")
	for _, p := range []string{reqPath, respPath} {
		if err := mkfifo(p); err != nil {
			b.Skipf("mkfifo unsupported: %v", err)
		}
	}
	// open ends. Open order avoids deadlock: open req(w) nonblock after server opens req(r).
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		reqR, err := os.OpenFile(reqPath, os.O_RDONLY, 0)
		if err != nil {
			return
		}
		respW, err := os.OpenFile(respPath, os.O_WRONLY, 0)
		if err != nil {
			return
		}
		buf := make([]byte, size)
		for i := 0; i < b.N; i++ {
			if _, err := readFullFile(reqR, buf); err != nil {
				return
			}
			if _, err := respW.Write(buf); err != nil {
				return
			}
		}
		reqR.Close()
		respW.Close()
	}()
	reqW, err := os.OpenFile(reqPath, os.O_WRONLY, 0)
	if err != nil {
		b.Fatal(err)
	}
	respR, err := os.OpenFile(respPath, os.O_RDONLY, 0)
	if err != nil {
		b.Fatal(err)
	}
	payload := make([]byte, size)
	echo := make([]byte, size)
	b.SetBytes(int64(size))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := reqW.Write(payload); err != nil {
			b.Fatal(err)
		}
		if _, err := readFullFile(respR, echo); err != nil {
			b.Fatal(err)
		}
	}
	b.StopTimer()
	reqW.Close()
	respR.Close()
	wg.Wait()
}

func readFullFile(f *os.File, buf []byte) (int, error) {
	got := 0
	for got < len(buf) {
		n, err := f.Read(buf[got:])
		if err != nil {
			return got, err
		}
		got += n
	}
	return got, nil
}

func BenchmarkFIFO_64B(b *testing.B)  { benchFIFO(b, 64) }
func BenchmarkFIFO_1KB(b *testing.B)  { benchFIFO(b, 1024) }
func BenchmarkFIFO_64KB(b *testing.B) { benchFIFO(b, 64*1024) }
func BenchmarkFIFO_1MB(b *testing.B)  { benchFIFO(b, 1024*1024) }
