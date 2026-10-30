package tokens

import (
	"carsharing/internal/domain"
	"context"
	"strings"

	"google.golang.org/grpc/metadata"
)

type TokenManager struct {
	jwtSecret []byte
}

func NewTokenManager(secret []byte) *TokenManager {
	return &TokenManager{jwtSecret: secret}
}

func (t *TokenManager) ExtractAuthToken(ctx context.Context) (string, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return "", domain.ErrInvalidAccessToken
	}

	authHeader := md.Get("authorization")
	if len(authHeader) == 0 {
		return "", domain.ErrInvalidAccessToken
	}

	if len(authHeader) != 1 {
		return "", domain.ErrInvalidAccessToken
	}

	parts := strings.SplitN(authHeader[0], " ", 2)

	if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
		return "", domain.ErrInvalidAccessToken
	}

	return parts[1], nil
}
