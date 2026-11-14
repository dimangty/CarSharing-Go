package mock

import (
	"context"
	"strings"

	"carsharing/internal/domain"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type MockAuthRepository struct{}

func NewMockAuthRepository() *MockAuthRepository {
	return &MockAuthRepository{}
}

func (r *MockAuthRepository) CreateUser(
	ctx context.Context,
	login, password, userIdentify string,
) (*domain.Auth, error) {
	return mockAuthentication(login, password)
}

func (r *MockAuthRepository) LoginUser(
	ctx context.Context,
	login, password, userIdentify string,
) (*domain.Auth, error) {
	return mockAuthentication(login, password)
}

func (r *MockAuthRepository) LogoutUser(
	ctx context.Context,
	userId int64,
	userIdentify string,
) error {
	return domain.ErrInvalidRefreshToken
}

func (r *MockAuthRepository) NewTokenUser(
	ctx context.Context,
	refreshToken, userIdentify string,
) (*domain.Auth, error) {
	return nil, domain.ErrInvalidRefreshToken
}

func mockAuthentication(login, password string) (*domain.Auth, error) {
	if strings.TrimSpace(login) == "" || strings.TrimSpace(password) == "" {
		return nil, status.Error(
			codes.InvalidArgument,
			"Username and password are required",
		)
	}

	return &domain.Auth{
		ID:           1,
		Name:         login,
		AccessToken:  "mock_access_token",
		RefreshToken: "mock_refresh_token",
	}, nil
}
