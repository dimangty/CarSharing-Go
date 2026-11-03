package service

import (
	"context"
	"strings"

	"carsharing/internal/domain"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// MockAuthService is stateless and deliberately has no repository, DB, Redis or
// token-issuer dependencies. Registration never creates even a temporary user.
type MockAuthService struct{}

func mockAuthentication(login, password string) (*domain.Auth, error) {
	if strings.TrimSpace(login) == "" || strings.TrimSpace(password) == "" {
		return nil, status.Error(codes.InvalidArgument, "Username and password are required")
	}
	return &domain.Auth{
		ID: 1, Name: login,
		AccessToken: "mock_access_token", RefreshToken: "mock_refresh_token",
	}, nil
}

func (*MockAuthService) CreateUser(_ context.Context, login, password, _ string) (*domain.Auth, error) {
	return mockAuthentication(login, password)
}

func (*MockAuthService) LoginUser(_ context.Context, login, password, _ string) (*domain.Auth, error) {
	return mockAuthentication(login, password)
}

func (*MockAuthService) LogoutUser(context.Context, int64, string) error {
	return status.Error(codes.Unimplemented, "Mock logout is not implemented")
}

func (*MockAuthService) NewTokenUser(context.Context, string, string) (*domain.Auth, error) {
	return nil, status.Error(codes.Unimplemented, "Mock refresh is not implemented")
}
