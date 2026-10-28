package domain

import (
	"time"
)

type Auth struct {
	ID 				int64
	Name			string
	RefreshToken	string
	AccessToken		string
}

type AuthRefreshToken struct {
    UserID             int64
    TokenValue         string
    UserIdentifyString string
    ExpiresAt          time.Time
    UsedAt             *time.Time // NULL is default value in table
}

