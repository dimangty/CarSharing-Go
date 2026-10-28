package interceptors

import (
	"context"
	"time"

	"carsharing/pkg/auth"

	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type UnaryBruteForceLimiterInterceptor struct {
	window *slidingWindow
}

// Allow records an attempt. The interceptor additionally releases the reservation
// after successful authentication or an infrastructure error.
func (u *UnaryBruteForceLimiterInterceptor) Allow(ctx context.Context, login string) (bool, error) {
	_, allowed, err := u.window.reserve(ctx, "brute:login:v2:"+login)
	return allowed, err
}

func NewUnaryBruteForceLimiterInterceptor(r *redis.Client, l int, w int, s string) (*UnaryBruteForceLimiterInterceptor, error) {
	window, err := newSlidingWindow(r, l, w, s)
	if err != nil {
		return nil, err
	}
	return &UnaryBruteForceLimiterInterceptor{window: window}, nil
}

func (u *UnaryBruteForceLimiterInterceptor) UnaryServerInterceptor(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
	var login string
	switch info.FullMethod {
	case auth.AuthService_SignIn_FullMethodName:
		if r, ok := req.(*auth.SignInRequest); ok {
			login = r.GetUserName()
		}
	case auth.AuthService_SignUp_FullMethodName:
		if r, ok := req.(*auth.SignUpRequest); ok {
			login = r.GetUserName()
		}
	default:
		return handler(ctx, req)
	}
	if login == "" {
		return nil, status.Error(codes.InvalidArgument, "Username is required")
	}
	key := "brute:login:v2:" + login
	id, allowed, err := u.window.reserve(ctx, key)
	if err != nil {
		return nil, status.Error(codes.Unavailable, "Brute-force limiter unavailable")
	}
	if !allowed {
		return nil, status.Error(codes.ResourceExhausted, "Too many authentication attempts")
	}

	resp, err := handler(ctx, req)
	if !authenticationFailed(resp, err) {
		// Refund only this attempt, preserving failures from concurrent requests.
		// A cancelled RPC must not prevent the refund of an infrastructure error.
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), time.Second)
		defer cancel()
		if releaseErr := u.window.rdb.ZRem(cleanupCtx, key, id).Err(); releaseErr != nil && err == nil {
			return nil, status.Error(codes.Unavailable, "Brute-force limiter unavailable")
		}
	}
	return resp, err
}

func authenticationFailed(resp any, err error) bool {
	if err != nil {
		switch status.Code(err) {
		case codes.Unauthenticated, codes.PermissionDenied, codes.InvalidArgument, codes.AlreadyExists:
			return true
		default:
			return false
		}
	}
	switch r := resp.(type) {
	case *auth.SignInResponse:
		return !r.GetSuccess()
	case *auth.SignUpResponse:
		return !r.GetSuccess()
	default:
		return false
	}
}
