package handler

import (
	"context"

	"carsharing/internal/domain"
	"carsharing/pkg/auth"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type AuthServiceInterface interface {
	CreateUser(
		ctx context.Context,
		login, password, userIdentify string,
	) (*domain.Auth, error)

	LoginUser(
		ctx context.Context,
		login, password, userIdentify string,
	) (*domain.Auth, error)

	LogoutUser(
		ctx context.Context,
		userId int64,
		userIdentify string,
	) error

	NewTokenUser(
		ctx context.Context,
		refreshToken, userIdentify string,
	) (*domain.Auth, error)
}

type AuthHandler struct {
	service AuthServiceInterface
	auth.UnimplementedAuthServiceServer
}

func NewAuthHandler(
	s AuthServiceInterface,
) *AuthHandler {
	return &AuthHandler{service: s}
}

func (a *AuthHandler) SignUp(
	ctx context.Context,
	req *auth.SignUpRequest,
) (*auth.SignUpResponse, error) {

	if req.GetUserPasswordConfirm() == "" ||
		req.GetUserPassword() != req.GetUserPasswordConfirm() {
		return nil, status.Error(
			codes.InvalidArgument,
			"Password confirmation must match",
		)
	}

	result, err := a.service.CreateUser(
		ctx,
		req.GetUserName(),
		req.GetUserPassword(),
		"",
	)
	if err != nil {
		return nil, err
	}

	return &auth.SignUpResponse{
		Success:      true,
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		Message:      "Mock registration successful",
	}, nil
}

func (a *AuthHandler) SignIn(
	ctx context.Context,
	req *auth.SignInRequest,
) (*auth.SignInResponse, error) {

	result, err := a.service.LoginUser(
		ctx,
		req.GetUserName(),
		req.GetUserPassword(),
		req.GetUserIdentifyString(),
	)
	if err != nil {
		return nil, err
	}

	return &auth.SignInResponse{
		Success:      true,
		AccessToken:  result.AccessToken,
		RefreshToken: result.RefreshToken,
		Message:      "Mock sign in successful",
	}, nil
}

func (a *AuthHandler) SignOut(
	context.Context,
	*auth.SignOutRequest,
) (*auth.SignOutResponse, error) {
	return nil, status.Error(
		codes.Unimplemented,
		"Mock sign out is not implemented",
	)
}

func (a *AuthHandler) AuthRefresh(
	context.Context,
	*auth.AuthRefreshRequest,
) (*auth.AuthRefreshResponse, error) {
	return nil, status.Error(
		codes.Unimplemented,
		"Mock refresh is not implemented",
	)
}
