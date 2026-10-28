package interceptors

import (
	"context"
	"net"

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
