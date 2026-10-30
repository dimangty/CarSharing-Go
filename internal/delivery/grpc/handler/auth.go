package handler

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"carsharing/internal/domain"
	"carsharing/pkg/auth"
)

type AuthServiceInterface interface {
	CreateUser(ctx context.Context, login string, password string, userIdentify string) (*domain.Auth, error)
	LoginUser(ctx context.Context, login string, password string, userIdentify string) (*domain.Auth, error)
	LogoutUser(ctx context.Context, userId int64, userIdentify string) error
	NewTokenUser(ctx context.Context, refreshToken string, userIdentify string) (*domain.Auth, error)
}

type AuthHandler struct {
	service AuthServiceInterface
	auth.UnimplementedAuthServiceServer
}

func NewAuthHandler(s AuthServiceInterface) *AuthHandler {
	return &AuthHandler{
		service: s,
	}
}

func (a *AuthHandler) SignUp(ctx context.Context, req *auth.SignUpRequest) (*auth.SignUpResponse, error) {

	return nil, status.Error(codes.Internal, "Something went wrong")
}

func (a *AuthHandler) SignIn(ctx context.Context, req *auth.SignInRequest) (*auth.SignInResponse, error) {

	return nil, status.Error(codes.Internal, "Something went wrong")
}

func (a *AuthHandler) SignOut(ctx context.Context, req *auth.SignOutRequest) (*auth.SignOutResponse, error) {
	return nil, status.Error(codes.Internal, "Something went wrong")
}

func (a *AuthHandler) AuthRefresh(ctx context.Context, req *auth.AuthRefreshRequest) (*auth.AuthRefreshResponse, error) {
	return nil, status.Error(codes.Internal, "Something went wrong")
}
