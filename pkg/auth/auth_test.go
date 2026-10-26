package auth

import (
	"encoding/hex"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func authMessageFixtures() []struct {
	name    string
	message proto.Message
	wireHex string
} {
	return []struct {
		name    string
		message proto.Message
		wireHex string
	}{
		{
			name: "SignInRequest",
			message: &SignInRequest{
				UserName: "n", UserPassword: "p", UserIdentifyString: "i",
			},
			wireHex: "0a016e1201701a0169",
		},
		{
			name: "SignInResponse",
			message: &SignInResponse{
				Success: true, RefreshToken: "r", AccessToken: "a", Message: "m",
			},
			wireHex: "08011201721a016122016d",
		},
		{
			name:    "SignOutRequest",
			message: &SignOutRequest{UserIdentify: "i"},
			wireHex: "0a0169",
		},
		{
			name:    "SignOutResponse",
			message: &SignOutResponse{Success: true, Message: "m"},
			wireHex: "080112016d",
		},
		{
			name: "SignUpRequest",
			message: &SignUpRequest{
				UserName: "n", UserPassword: "p", UserPasswordConfirm: "c",
			},
			wireHex: "0a016e1201701a0163",
		},
		{
			name: "SignUpResponse",
			message: &SignUpResponse{
				Success: true, RefreshToken: "r", AccessToken: "a", Message: "m",
			},
			wireHex: "08011201721a016122016d",
		},
		{
			name:    "AuthRefreshRequest",
			message: &AuthRefreshRequest{RefreshToken: "r"},
			wireHex: "0a0172",
		},
		{
			name: "AuthRefreshResponse",
			message: &AuthRefreshResponse{
				Success: true, RefreshToken: "r", AccessToken: "a",
			},
			wireHex: "08011201721a0161",
		},
	}
}

func TestAuthMessagesWireCompatibility(t *testing.T) {
	// Literal wire fixtures catch changed field numbers, types and field mapping
	// that a marshal/unmarshal round trip through the same schema would miss.
	for _, tt := range authMessageFixtures() {
		t.Run(tt.name, func(t *testing.T) {
			wire, err := hex.DecodeString(tt.wireHex)
			require.NoError(t, err)

			t.Run("marshal", func(t *testing.T) {
				got, err := proto.Marshal(tt.message)
				require.NoError(t, err)
				require.Equal(t, wire, got)
			})

			t.Run("unmarshal", func(t *testing.T) {
				got := tt.message.ProtoReflect().Type().New().Interface()
				require.NoError(t, proto.Unmarshal(wire, got))
				require.True(t, proto.Equal(tt.message, got), "decoded message: %v", got)
			})
		})
	}
}

func TestAuthMessagesProto3Defaults(t *testing.T) {
	for _, tt := range authMessageFixtures() {
		t.Run(tt.name, func(t *testing.T) {
			zero := tt.message.ProtoReflect().Type().New().Interface()
			wire, err := proto.Marshal(zero)
			require.NoError(t, err)
			require.Empty(t, wire)

			// Decode into a populated message to also check that absent fields
			// do not leave credentials or tokens from an earlier response.
			got := proto.Clone(tt.message)
			require.NoError(t, proto.Unmarshal(nil, got))
			require.True(t, proto.Equal(zero, got), "decoded defaults: %v", got)
		})
	}
}

func TestAuthMessagePreservesUnknownFields(t *testing.T) {
	// Field 1 contains "r"; unknown field 99 contains varint 7.
	wire := []byte{0x0a, 0x01, 'r', 0x98, 0x06, 0x07}
	var request AuthRefreshRequest
	require.NoError(t, proto.Unmarshal(wire, &request))
	require.Equal(t, "r", request.RefreshToken)
	require.Equal(t, []byte{0x98, 0x06, 0x07}, []byte(request.ProtoReflect().GetUnknown()))

	encoded, err := proto.Marshal(&request)
	require.NoError(t, err)
	var decoded AuthRefreshRequest
	require.NoError(t, proto.Unmarshal(encoded, &decoded))
	require.Equal(t, "r", decoded.RefreshToken)
	require.Equal(t, []byte{0x98, 0x06, 0x07}, []byte(decoded.ProtoReflect().GetUnknown()))
}
