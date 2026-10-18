package interceptors

import (
	"context"
	"log"
	"net"
	"os"
	"fmt"

	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

type UnaryRateLimiterInterceptor struct {
	rdb 	*redis.Client
	limit 	int
	window 	int
	sha 	string
}

func (u *UnaryRateLimiterInterceptor) Allow(ctx context.Context, ip string) (bool, error) {
	result, err := u.rdb.EvalSha(ctx, u.sha, []string{fmt.Sprintf("rate:ip:%s", ip)}, u.limit, u.window).Result()
	if err != nil {
		return false, err
	}

	return result.(int64) == 1, nil
}

func NewUnaryRateLimiterInterceptor(r *redis.Client, l int, w int, s string) (*UnaryRateLimiterInterceptor, error) {
	content, err := os.ReadFile(s)
	if err != nil {
		return nil, err
	}
	sha, err := r.ScriptLoad(context.Background(), string(content)).Result()
	if err != nil {
		return nil, err
	}
	return &UnaryRateLimiterInterceptor{rdb: r, limit: l, window: w, sha: sha}, nil
}

func (u *UnaryRateLimiterInterceptor)UnaryServerInterceptor(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
    log.Printf("[INTERCEPTOR][RateLimiter]: Received request on method: %s", info.FullMethod)

// get ip
	p, ok := peer.FromContext(ctx)
	if !ok {
		return nil, status.Error(codes.Internal, "Failed to get peer info")
	}

	clientIP, _, err := net.SplitHostPort(p.Addr.String())
	if err != nil {
		clientIP = p.Addr.String()
	}

	log.Printf("[RateLimiter] Real TCP IP detected: %s", clientIP)

	allowed, err := u.Allow(ctx, clientIP)
	if err != nil {
		return nil, err
	}

	if !allowed {
		return nil, status.Error(codes.ResourceExhausted, "Limit exhausted")
	}

    resp, err := handler(ctx, req)
    log.Printf("[INTERCEPTOR][RateLimiter]: Sending response from method: %s", info.FullMethod)

    return resp, err
}
