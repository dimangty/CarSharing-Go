package interceptors

import (
	"context"
	"crypto/rand"
	"fmt"
	"net"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

type UnaryRateLimiterInterceptor struct {
	window *slidingWindow
}

func (u *UnaryRateLimiterInterceptor) Allow(ctx context.Context, ip string) (bool, error) {
	// Versioned keys avoid WRONGTYPE errors from the previous string counters.
	_, allowed, err := u.window.reserve(ctx, "rate:ip:v2:"+ip)
	return allowed, err
}

func NewUnaryRateLimiterInterceptor(r *redis.Client, l int, w int, s string) (*UnaryRateLimiterInterceptor, error) {
	window, err := newSlidingWindow(r, l, w, s)
	if err != nil {
		return nil, err
	}
	return &UnaryRateLimiterInterceptor{window: window}, nil
}

func (u *UnaryRateLimiterInterceptor) UnaryServerInterceptor(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
	p, ok := peer.FromContext(ctx)
	if !ok || p.Addr == nil {
		return nil, status.Error(codes.Internal, "Failed to get peer info")
	}

	clientIP, _, err := net.SplitHostPort(p.Addr.String())
	if err != nil {
		clientIP = p.Addr.String()
	}

	allowed, err := u.Allow(ctx, clientIP)
	if err != nil {
		return nil, status.Error(codes.Unavailable, "Rate limiter unavailable")
	}

	if !allowed {
		return nil, status.Error(codes.ResourceExhausted, "Limit exhausted")
	}
	return handler(ctx, req)
}

type slidingWindow struct {
	rdb    *redis.Client
	script *redis.Script
	limit  int
	window int // seconds
}

func newSlidingWindow(rdb *redis.Client, limit, window int, path string) (*slidingWindow, error) {
	if rdb == nil || limit <= 0 || window <= 0 {
		return nil, fmt.Errorf("Redis client, positive limit and positive window are required")
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	script := redis.NewScript(string(content))
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := script.Load(ctx, rdb).Err(); err != nil {
		return nil, err
	}
	return &slidingWindow{rdb: rdb, script: script, limit: limit, window: window}, nil
}

func (w *slidingWindow) reserve(ctx context.Context, key string) (string, bool, error) {
	id := rand.Text()
	result, err := w.script.Run(ctx, w.rdb, []string{key}, w.limit, w.window, id).Int64()
	return id, result == 1, err
}
