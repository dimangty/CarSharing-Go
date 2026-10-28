package interceptors

import (
	"context"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

// MetadataTokenExtractor reads a single Authorization: Bearer <JWT> header.
type MetadataTokenExtractor struct{}

func (MetadataTokenExtractor) ExtractAuthToken(ctx context.Context) (string, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok || len(md.Get("authorization")) != 1 {
		return "", status.Error(codes.Unauthenticated, "A single authorization header is required")
	}
	fields := strings.Fields(md.Get("authorization")[0])
	if len(fields) != 2 || !strings.EqualFold(fields[0], "Bearer") {
		return "", status.Error(codes.Unauthenticated, "Expected Bearer token")
	}
	return fields[1], nil
}
