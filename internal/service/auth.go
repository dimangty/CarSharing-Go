package service

import (
	"context"

	"carsharing/internal/domain"

	"golang.org/x/crypto/bcrypt"
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
	passwordHash, err := bcrypt.GenerateFromPassword(
		[]byte(password),
		bcrypt.DefaultCost,
	)
	if err != nil {
		return nil, domain.ErrInternal
	}

	return a.repo.CreateUser(ctx, login, string(passwordHash), userIdentify)
}

func (a *AuthService) LoginUser(
	ctx context.Context,
	login, password, userIdentify string,
) (*domain.Auth, error) {
	passwordHash, err := bcrypt.GenerateFromPassword(
		[]byte(password),
		bcrypt.DefaultCost,
	)
	if err != nil {
		return nil, domain.ErrInternal
	}

	return a.repo.LoginUser(ctx, login, string(passwordHash), userIdentify)
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
