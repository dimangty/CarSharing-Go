package interceptors

import (
	"context"
	"errors"
	"os"

	"carsharing/internal/domain"
	"carsharing/pkg/auth"

	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type jwtExtractor interface {
	ExtractAuthToken(ctx context.Context) (string, error)
}

type AuthTokenFields struct {
	UserID int64 `json:"user_id"`
	jwt.RegisteredClaims
}

type UnaryTokenInterceptor struct {
	rdb            *redis.Client
	tokenExtractor jwtExtractor
	secret         []byte
}

func NewUnaryTokenInterceptor(db *redis.Client, extractor jwtExtractor) *UnaryTokenInterceptor {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "jwt-secret"
	}
	return &UnaryTokenInterceptor{rdb: db, tokenExtractor: extractor, secret: []byte(secret)}
}

func (u *UnaryTokenInterceptor) UnaryServerInterceptor(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
	switch info.FullMethod {
	case auth.AuthService_SignIn_FullMethodName, auth.AuthService_SignUp_FullMethodName, auth.AuthService_AuthRefresh_FullMethodName:
		return handler(ctx, req)
	}

	// no authorization field or invalid field format
	token, err := u.tokenExtractor.ExtractAuthToken(ctx)
	if err != nil {
		return nil, err
	}

	jwtToken, err := jwt.ParseWithClaims(token, &AuthTokenFields{}, func(token *jwt.Token) (interface{}, error) {
		return u.secret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}), jwt.WithExpirationRequired())
	if err != nil {
		return nil, status.Error(codes.Unauthenticated, "Invalid or expired token")
	}

	claims, ok := jwtToken.Claims.(*AuthTokenFields)
	if !ok || !jwtToken.Valid || claims.UserID <= 0 {
		return nil, status.Error(codes.Unauthenticated, "Invalid token")
	}

	_, err = u.rdb.Get(ctx, "stoplist:token:"+token).Result()
	switch {
	case err == nil:
		return nil, status.Error(codes.Unauthenticated, "Token in stop-list")
	case !errors.Is(err, redis.Nil):
		return nil, status.Error(codes.Unavailable, "Token stop-list unavailable")
	}

	return handler(context.WithValue(ctx, domain.UserIDKey, claims.UserID), req)
}
