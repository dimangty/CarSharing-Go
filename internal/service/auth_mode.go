package service

import (
	"context"
	"fmt"
	"strconv"

	"carsharing/internal/domain"
)

// AuthenticationService is the existing auth handler's business boundary.
type AuthenticationService interface {
	CreateUser(context.Context, string, string, string) (*domain.Auth, error)
	LoginUser(context.Context, string, string, string) (*domain.Auth, error)
	LogoutUser(context.Context, int64, string) error
	NewTokenUser(context.Context, string, string) (*domain.Auth, error)
}

// SelectAuthService fails closed: a client cannot select the server's auth mode.
func SelectAuthService(environment, mockEnabled string) (AuthenticationService, error) {
	enabled := false
	if mockEnabled != "" {
		var err error
		enabled, err = strconv.ParseBool(mockEnabled)
		if err != nil {
			return nil, fmt.Errorf("invalid AUTH_MOCK_ENABLED: %w", err)
		}
	}
	if enabled {
		if environment != "development" && environment != "test" {
			return nil, fmt.Errorf("AUTH_MOCK_ENABLED requires APP_ENV=development or APP_ENV=test")
		}
		return &MockAuthService{}, nil
	}
	return NewAuthRepository(), nil
}
