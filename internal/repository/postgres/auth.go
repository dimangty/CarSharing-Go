package postgres

import (
	"context"
	"errors"
	"strings"

	"carsharing/internal/domain"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type AuthRepository struct {
	pool *pgxpool.Pool
}

func NewAuthRepository(pool *pgxpool.Pool) *AuthRepository {
	return &AuthRepository{pool: pool}
}

func (r *AuthRepository) CreateUser(
	ctx context.Context,
	login, passwordHash, userIdentify string,
) (*domain.Auth, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	const query = `
		INSERT INTO users (login, password_hash)
		VALUES ($1, $2)
		ON CONFLICT (login) DO NOTHING
		RETURNING id, login
	`

	var userID int64
	var userName string

	err := r.pool.QueryRow(ctx, query, login, passwordHash).
		Scan(&userID, &userName)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrUserAlreadyExists
	}

	if err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return nil, ctxErr
		}
		return nil, domain.ErrInternal
	}

	return mockAuthentication(userID, userName), nil
}

func (r *AuthRepository) LoginUser(
	ctx context.Context,
	login, password, userIdentify string,
) (*domain.Auth, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if strings.TrimSpace(login) == "" ||
		strings.TrimSpace(password) == "" ||
		len(password) > 72 {
		return nil, domain.ErrInvalidCredentials
	}

	const query = `
		SELECT id, login, password_hash
		FROM users
		WHERE login = $1
	`

	var userID int64
	var userName, passwordHash string

	err := r.pool.QueryRow(ctx, query, login).
		Scan(&userID, &userName, &passwordHash)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrInvalidCredentials
	}
	if err != nil {
		return nil, domain.ErrInternal
	}

	err = bcrypt.CompareHashAndPassword(
		[]byte(passwordHash),
		[]byte(password),
	)
	if ctxErr := ctx.Err(); ctxErr != nil {
		return nil, ctxErr
	}
	if errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) {
		return nil, domain.ErrInvalidCredentials
	}
	if err != nil {
		return nil, domain.ErrInternal
	}

	return mockAuthentication(userID, userName), nil
}

func (r *AuthRepository) LogoutUser(
	ctx context.Context,
	userId int64,
	userIdentify string,
) error {
	return domain.ErrInvalidRefreshToken
}

func (r *AuthRepository) NewTokenUser(
	ctx context.Context,
	refreshToken, userIdentify string,
) (*domain.Auth, error) {
	return nil, domain.ErrInvalidRefreshToken
}

func mockAuthentication(userID int64, login string) *domain.Auth {
	return &domain.Auth{
		ID:           userID,
		Name:         login,
		AccessToken:  "mock_access_token",
		RefreshToken: "mock_refresh_token",
	}
}
