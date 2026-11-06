package service

import (
	"context"
	"strings"
	"time"

	"carsharing/internal/domain"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type AuthRepositoryInterface interface {
	CreateUser(ctx context.Context, login string, hashedPwd string) (int64, error)
	// id, hashed_pwd
	LoginUser(ctx context.Context, login string) (int64, string, error)

	AddToken(ctx context.Context, token *domain.AuthRefreshToken) error
	UpdateToken(ctx context.Context, userId int64, refreshToken string, updateAt time.Time) error
	RevokeTokens(ctx context.Context, userId int64) error
	RevokeToken(ctx context.Context, userId int64, userIdentify string) error
	GetLastActiveToken(ctx context.Context, userId int64, userIdentify string) (string, error)
	GetToken(ctx context.Context, token string) (*domain.AuthRefreshToken, error)
}

type AuthTokenInterface interface {
	GenerateRefreshToken() string
	JWTByUserID(id int64) (string, error)
}

type AuthService struct {
	repo  AuthRepositoryInterface
	tkMgr AuthTokenInterface
}

type AuthRepository struct {
	db string
}

func NewAuthRepository() *AuthRepository {
	return &AuthRepository{
		db: "",
	}
}

func NewAuthService(r AuthRepositoryInterface, t AuthTokenInterface) *AuthService {
	return &AuthService{
		repo:  r,
		tkMgr: t,
	}
}

func (a *AuthService) CreateUser(ctx context.Context, login string, password string, userIdentify string) (*domain.Auth, error) {
	return mockAuthentication(login, password)
}

func (a *AuthService) LoginUser(ctx context.Context, login string, password string, userIdentify string) (*domain.Auth, error) {

	return mockAuthentication(login, password)
}

func (a *AuthService) LogoutUser(ctx context.Context, userId int64, userIdentify string) error {
	return domain.ErrInvalidRefreshToken
}

func (a *AuthService) NewTokenUser(ctx context.Context, refreshToken string, userIdentify string) (*domain.Auth, error) {
	return nil, domain.ErrInvalidRefreshToken
}

func mockAuthentication(login, password string) (*domain.Auth, error) {
	if strings.TrimSpace(login) == "" || strings.TrimSpace(password) == "" {
		return nil, status.Error(codes.InvalidArgument, "Username and password are required")
	}
	return &domain.Auth{
		ID: 1, Name: login,
		AccessToken: "mock_access_token", RefreshToken: "mock_refresh_token",
	}, nil
}
