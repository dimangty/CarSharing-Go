package service

import (
	"context"

	"carsharing/internal/domain"
)

type AuthRepositoryInterface interface {
	CreateUser(ctx context.Context, login, password, userIdentify string) (*domain.Auth, error)
	LoginUser(ctx context.Context, login, password, userIdentify string) (*domain.Auth, error)
	LogoutUser(ctx context.Context, userId int64, userIdentify string) error
	NewTokenUser(ctx context.Context, refreshToken, userIdentify string) (*domain.Auth, error)
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

func (a *AuthService) CreateUser(
	ctx context.Context,
	login, password, userIdentify string,
) (*domain.Auth, error) {
	return a.repo.CreateUser(ctx, login, password, userIdentify)
}

func (a *AuthService) LoginUser(
	ctx context.Context,
	login, password, userIdentify string,
) (*domain.Auth, error) {
	return a.repo.LoginUser(ctx, login, password, userIdentify)
}

func (a *AuthService) LogoutUser(
	ctx context.Context,
	userId int64,
	userIdentify string,
) error {
	return a.repo.LogoutUser(ctx, userId, userIdentify)
}

func (a *AuthService) NewTokenUser(
	ctx context.Context,
	refreshToken, userIdentify string,
) (*domain.Auth, error) {
	return a.repo.NewTokenUser(ctx, refreshToken, userIdentify)
}
