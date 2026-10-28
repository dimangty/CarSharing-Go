package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"carsharing/internal/delivery/grpc/interceptors"

	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
)

func main() {
	addr := flag.String("addr", ":50051", "gRPC listen address")
	flag.Parse()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, *addr); err != nil {
		log.Fatal(err)
	}
}

func run(ctx context.Context, addr string) error {
	redisAddr := os.Getenv("REDIS_CONN_STR")
	if redisAddr == "" {
		redisAddr = "localhost:6380"
	}
	rdb := redis.NewClient(&redis.Options{Addr: redisAddr})
	defer rdb.Close()
	if err := rdb.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("ping Redis: %w", err)
	}
	rate, err := interceptors.NewUnaryRateLimiterInterceptor(rdb, 10, 60, "scripts/lua/rate_limiter.lua")
	if err != nil {
		return fmt.Errorf("create rate limiter: %w", err)
	}
	brute, err := interceptors.NewUnaryBruteForceLimiterInterceptor(rdb, 5, 30, "scripts/lua/rate_limiter.lua")
	if err != nil {
		return fmt.Errorf("create brute-force limiter: %w", err)
	}
	token := interceptors.NewUnaryTokenInterceptor(rdb, interceptors.MetadataTokenExtractor{})
	server := grpc.NewServer(grpc.ChainUnaryInterceptor(
		rate.UnaryServerInterceptor,
		brute.UnaryServerInterceptor,
		token.UnaryServerInterceptor,
	))
	defer server.Stop()
	lis, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	defer lis.Close()
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			server.GracefulStop()
		case <-done:
		}
	}()
	log.Printf("[SERVER] gRPC server listening on %s (rate → brute-force → auth)", lis.Addr())
	if err := server.Serve(lis); err != nil && !errors.Is(err, grpc.ErrServerStopped) {
		return fmt.Errorf("serve gRPC: %w", err)
	}
	log.Print("[SERVER] Stopped")
	return nil
}