package pipebench

import (
	"net"
	"path/filepath"
	"sync"
	"testing"
)

// udsPair returns a connected UDS client/server conn pair + cleanup.
func udsPair(b *testing.B) (net.Conn, net.Conn, func()) {
	dir := b.TempDir()
	sock := filepath.Join(dir, "s.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		b.Fatal(err)
	}
	type res struct {
		c   net.Conn
		err error
	}
	ch := make(chan res, 1)
	go func() { c, err := ln.Accept(); ch <- res{c, err} }()
	client, err := net.Dial("unix", sock)
	if err != nil {
		b.Fatal(err)
	}
	srv := <-ch
	if srv.err != nil {
		b.Fatal(srv.err)
	}
	return client, srv.c, func() { client.Close(); srv.c.Close(); ln.Close() }
}

// Send throughput: timed loop writes frames; background drains.
func benchUDSSend(b *testing.B, size int) {
	c1, c2, done := udsPair(b)
	defer done()
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		buf := make([]byte, size)
		for {
			if _, err := c2.Read(buf); err != nil {
				return
			}
		}
	}()
	payload := make([]byte, size)
	b.SetBytes(int64(size))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := c1.Write(payload); err != nil {
			b.Fatal(err)
		}
	}
	b.StopTimer()
	c1.Close()
	wg.Wait()
}

// Recv throughput: timed loop reads frames; background floods.
func benchUDSRecv(b *testing.B, size int) {
	c1, c2, done := udsPair(b)
	defer done()
	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		payload := make([]byte, size)
		for {
			select {
			case <-stop:
				return
			default:
			}
			if _, err := c2.Write(payload); err != nil {
				return
			}
		}
	}()
	buf := make([]byte, size)
	b.SetBytes(int64(size))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := readFull(c1, buf); err != nil {
			b.Fatal(err)
		}
	}
	b.StopTimer()
	close(stop)
	c2.Close()
	c1.Close()
	wg.Wait()
}

// Connect: timed Dial+Close against an accept loop.
func benchUDSConnect(b *testing.B) {
	dir := b.TempDir()
	sock := filepath.Join(dir, "s.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		b.Fatal(err)
	}
	defer ln.Close()
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			c.Close()
		}
	}()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		c, err := net.Dial("unix", sock)
		if err != nil {
			b.Fatal(err)
		}
		c.Close()
	}
	b.StopTimer()
	ln.Close()
	wg.Wait()
}

func BenchmarkUDSSend_64B(b *testing.B)  { benchUDSSend(b, 64) }
func BenchmarkUDSSend_1KB(b *testing.B)  { benchUDSSend(b, 1024) }
func BenchmarkUDSSend_4KB(b *testing.B)  { benchUDSSend(b, 4096) }
func BenchmarkUDSSend_64KB(b *testing.B) { benchUDSSend(b, 64*1024) }

func BenchmarkUDSRecv_64B(b *testing.B)  { benchUDSRecv(b, 64) }
func BenchmarkUDSRecv_1KB(b *testing.B)  { benchUDSRecv(b, 1024) }
func BenchmarkUDSRecv_4KB(b *testing.B)  { benchUDSRecv(b, 4096) }
func BenchmarkUDSRecv_64KB(b *testing.B) { benchUDSRecv(b, 64*1024) }

func BenchmarkUDSRT_4KB(b *testing.B) { benchUDS(b, 4096) }

func BenchmarkUDSConnect(b *testing.B) { benchUDSConnect(b) }
