package winpipebench

import (
	"net"
	"sync"
	"testing"

	winio "github.com/Microsoft/go-winio"
)

const pipePath = `\\.\pipe\motadata-bench2`

func pipePair(b *testing.B) (net.Conn, net.Conn, func()) {
	ln, err := winio.ListenPipe(pipePath, &winio.PipeConfig{
		InputBufferSize:  65536,
		OutputBufferSize: 65536,
	})
	if err != nil {
		b.Fatal(err)
	}
	type res struct {
		c   net.Conn
		err error
	}
	ch := make(chan res, 1)
	go func() { c, err := ln.Accept(); ch <- res{c, err} }()
	client, err := winio.DialPipe(pipePath, nil)
	if err != nil {
		b.Fatal(err)
	}
	srv := <-ch
	if srv.err != nil {
		b.Fatal(srv.err)
	}
	return client, srv.c, func() { client.Close(); srv.c.Close(); ln.Close() }
}

func benchPipeSend(b *testing.B, size int) {
	c1, c2, done := pipePair(b)
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

func benchPipeRecv(b *testing.B, size int) {
	c1, c2, done := pipePair(b)
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

func benchPipeConnect(b *testing.B) {
	ln, err := winio.ListenPipe(pipePath, &winio.PipeConfig{})
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
		c, err := winio.DialPipe(pipePath, nil)
		if err != nil {
			b.Fatal(err)
		}
		c.Close()
	}
	b.StopTimer()
	ln.Close()
	wg.Wait()
}

func BenchmarkPipeSend_64B(b *testing.B)  { benchPipeSend(b, 64) }
func BenchmarkPipeSend_1KB(b *testing.B)  { benchPipeSend(b, 1024) }
func BenchmarkPipeSend_4KB(b *testing.B)  { benchPipeSend(b, 4096) }
func BenchmarkPipeSend_64KB(b *testing.B) { benchPipeSend(b, 64*1024) }

func BenchmarkPipeRecv_64B(b *testing.B)  { benchPipeRecv(b, 64) }
func BenchmarkPipeRecv_1KB(b *testing.B)  { benchPipeRecv(b, 1024) }
func BenchmarkPipeRecv_4KB(b *testing.B)  { benchPipeRecv(b, 4096) }
func BenchmarkPipeRecv_64KB(b *testing.B) { benchPipeRecv(b, 64*1024) }

func BenchmarkPipeRT_4KB(b *testing.B) { benchPipeRoundTrip(b, 4096) }

func BenchmarkPipeConnect(b *testing.B) { benchPipeConnect(b) }
