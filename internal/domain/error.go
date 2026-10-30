package domain

import (
	"errors"
)

var (
	ErrUserNotFound        = errors.New("user not found in database")
	ErrInvalidCredentials  = errors.New("invalid login or password")
	ErrUserAlreadyExists   = errors.New("user with this login already exists")
	ErrTokenExpired        = errors.New("session token has expired")
	ErrInvalidAccessToken  = errors.New("Auth token is corrupted or invalid")
	ErrInvalidRefreshToken = errors.New("Refresh token is expired or invalid")
	ErrStolenRefreshToken  = errors.New("Get your hands off my token!")
	ErrInternal            = errors.New("internal server error")
)
