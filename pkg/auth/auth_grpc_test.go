package auth

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

type authContextKey struct{}

type authRPCFixture struct {
	name       string
	method     string
	request    proto.Message
	response   proto.Message
	clientCall func(context.Context, AuthServiceClient, proto.Message, ...grpc.CallOption) (proto.Message, error)
	handler    func(any, context.Context, func(any) error, grpc.UnaryServerInterceptor) (any, error)
	setHandler func(*authServerStub, func(context.Context, proto.Message) (proto.Message, error))
}

func authRPCFixtures() []authRPCFixture {
	return []authRPCFixture{
		{
			name: "SignIn", method: "/auth.AuthService/SignIn",
			request:  &SignInRequest{UserName: "alice", UserPassword: "password", UserIdentifyString: "device"},
			response: &SignInResponse{Success: true, RefreshToken: "refresh", AccessToken: "access", Message: "signed in"},
			clientCall: func(ctx context.Context, client AuthServiceClient, request proto.Message, opts ...grpc.CallOption) (proto.Message, error) {
				return client.SignIn(ctx, request.(*SignInRequest), opts...)
			},
			handler: _AuthService_SignIn_Handler,
			setHandler: func(server *authServerStub, call func(context.Context, proto.Message) (proto.Message, error)) {
				server.signIn = func(ctx context.Context, request *SignInRequest) (*SignInResponse, error) {
					response, err := call(ctx, request)
					if response == nil {
						return nil, err
					}
					return response.(*SignInResponse), err
				}
			},
		},
		{
			name: "SignUp", method: "/auth.AuthService/SignUp",
			request:  &SignUpRequest{UserName: "bob", UserPassword: "password", UserPasswordConfirm: "password"},
			response: &SignUpResponse{Success: true, RefreshToken: "refresh", AccessToken: "access", Message: "signed up"},
			clientCall: func(ctx context.Context, client AuthServiceClient, request proto.Message, opts ...grpc.CallOption) (proto.Message, error) {
				return client.SignUp(ctx, request.(*SignUpRequest), opts...)
			},
			handler: _AuthService_SignUp_Handler,
			setHandler: func(server *authServerStub, call func(context.Context, proto.Message) (proto.Message, error)) {
				server.signUp = func(ctx context.Context, request *SignUpRequest) (*SignUpResponse, error) {
					response, err := call(ctx, request)
					if response == nil {
						return nil, err
					}
					return response.(*SignUpResponse), err
				}
			},
		},
		{
			name: "SignOut", method: "/auth.AuthService/SignOut",
			request:  &SignOutRequest{UserIdentify: "device"},
			response: &SignOutResponse{Success: true, Message: "signed out"},
			clientCall: func(ctx context.Context, client AuthServiceClient, request proto.Message, opts ...grpc.CallOption) (proto.Message, error) {
				return client.SignOut(ctx, request.(*SignOutRequest), opts...)
			},
			handler: _AuthService_SignOut_Handler,
			setHandler: func(server *authServerStub, call func(context.Context, proto.Message) (proto.Message, error)) {
				server.signOut = func(ctx context.Context, request *SignOutRequest) (*SignOutResponse, error) {
					response, err := call(ctx, request)
					if response == nil {
						return nil, err
					}
					return response.(*SignOutResponse), err
				}
			},
		},
		{
			name: "AuthRefresh", method: "/auth.AuthService/AuthRefresh",
			request:  &AuthRefreshRequest{RefreshToken: "old-refresh"},
			response: &AuthRefreshResponse{Success: true, RefreshToken: "new-refresh", AccessToken: "new-access"},
			clientCall: func(ctx context.Context, client AuthServiceClient, request proto.Message, opts ...grpc.CallOption) (proto.Message, error) {
				return client.AuthRefresh(ctx, request.(*AuthRefreshRequest), opts...)
			},
			handler: _AuthService_AuthRefresh_Handler,
			setHandler: func(server *authServerStub, call func(context.Context, proto.Message) (proto.Message, error)) {
				server.authRefresh = func(ctx context.Context, request *AuthRefreshRequest) (*AuthRefreshResponse, error) {
					response, err := call(ctx, request)
					if response == nil {
						return nil, err
					}
					return response.(*AuthRefreshResponse), err
				}
			},
		},
	}
}

type authClientConnStub struct {
	t      *testing.T
	invoke func(context.Context, string, any, any, ...grpc.CallOption) error
}

func (s *authClientConnStub) Invoke(ctx context.Context, method string, request, response any, opts ...grpc.CallOption) error {
	return s.invoke(ctx, method, request, response, opts...)
}

func (s *authClientConnStub) NewStream(context.Context, *grpc.StreamDesc, string, ...grpc.CallOption) (grpc.ClientStream, error) {
	s.t.Fatal("unexpected streaming call for a unary auth RPC")
	return nil, nil
}

func TestAuthServiceClient(t *testing.T) {
	for _, tt := range authRPCFixtures() {
		t.Run(tt.name, func(t *testing.T) {
			for _, withOptions := range []bool{false, true} {
				name := "success_without_options"
				if withOptions {
					name = "success_with_options"
				}
				t.Run(name, func(t *testing.T) {
					ctx := context.WithValue(t.Context(), authContextKey{}, "client")
					input := proto.Clone(tt.request)
					wantRequest := proto.Clone(input)
					var headers, trailers metadata.MD
					var options []grpc.CallOption
					if withOptions {
						options = []grpc.CallOption{grpc.Header(&headers), grpc.Trailer(&trailers)}
					}
					originalOptions := append([]grpc.CallOption(nil), options...)
					calls := 0
					var allocatedResponse any
					conn := &authClientConnStub{t: t, invoke: func(gotCtx context.Context, method string, request, response any, opts ...grpc.CallOption) error {
						calls++
						require.Same(t, ctx, gotCtx)
						require.Equal(t, tt.method, method)
						require.Same(t, input, request)
						require.True(t, proto.Equal(wantRequest, request.(proto.Message)), "request was modified before Invoke")
						require.IsType(t, tt.response, response)
						require.Len(t, opts, 1+len(options))
						require.IsType(t, grpc.StaticMethodCallOption{}, opts[0])
						if withOptions {
							require.IsType(t, grpc.HeaderCallOption{}, opts[1])
							require.IsType(t, grpc.TrailerCallOption{}, opts[2])
							require.Same(t, &headers, opts[1].(grpc.HeaderCallOption).HeaderAddr)
							require.Same(t, &trailers, opts[2].(grpc.TrailerCallOption).TrailerAddr)
						}
						allocatedResponse = response
						proto.Merge(response.(proto.Message), tt.response)
						return nil
					}}

					response, err := tt.clientCall(ctx, NewAuthServiceClient(conn), input, options...)
					require.NoError(t, err)
					require.Equal(t, 1, calls)
					require.Same(t, allocatedResponse, response)
					require.True(t, proto.Equal(tt.response, response), "response: %v", response)
					require.True(t, proto.Equal(wantRequest, input), "request was modified by the client")
					require.Equal(t, originalOptions, options)
				})
			}

			for _, failure := range []struct {
				name string
				err  error
			}{
				{name: "status_error", err: status.Error(codes.Unavailable, "connection unavailable")},
				{name: "context_error", err: context.Canceled},
			} {
				t.Run(failure.name, func(t *testing.T) {
					ctx := t.Context()
					input := proto.Clone(tt.request)
					wantRequest := proto.Clone(input)
					calls := 0
					conn := &authClientConnStub{t: t, invoke: func(gotCtx context.Context, method string, request, response any, _ ...grpc.CallOption) error {
						calls++
						require.Same(t, ctx, gotCtx)
						require.Equal(t, tt.method, method)
						require.Same(t, input, request)
						require.True(t, proto.Equal(wantRequest, request.(proto.Message)), "request was modified before Invoke")
						require.IsType(t, tt.response, response)
						// Even a partially populated reply must not escape on error.
						proto.Merge(response.(proto.Message), tt.response)
						return failure.err
					}}

					response, err := tt.clientCall(ctx, NewAuthServiceClient(conn), input)
					require.Same(t, failure.err, err)
					require.Nil(t, response)
					require.True(t, proto.Equal(wantRequest, input), "request was modified by the client")
					require.Equal(t, 1, calls)
				})
			}
		})
	}
}

type authServerStub struct {
	UnimplementedAuthServiceServer
	t           *testing.T
	signIn      func(context.Context, *SignInRequest) (*SignInResponse, error)
	signUp      func(context.Context, *SignUpRequest) (*SignUpResponse, error)
	signOut     func(context.Context, *SignOutRequest) (*SignOutResponse, error)
	authRefresh func(context.Context, *AuthRefreshRequest) (*AuthRefreshResponse, error)
}

func (s *authServerStub) SignIn(ctx context.Context, request *SignInRequest) (*SignInResponse, error) {
	require.NotNil(s.t, s.signIn, "unexpected SignIn call")
	return s.signIn(ctx, request)
}

func (s *authServerStub) SignUp(ctx context.Context, request *SignUpRequest) (*SignUpResponse, error) {
	require.NotNil(s.t, s.signUp, "unexpected SignUp call")
	return s.signUp(ctx, request)
}

func (s *authServerStub) SignOut(ctx context.Context, request *SignOutRequest) (*SignOutResponse, error) {
	require.NotNil(s.t, s.signOut, "unexpected SignOut call")
	return s.signOut(ctx, request)
}

func (s *authServerStub) AuthRefresh(ctx context.Context, request *AuthRefreshRequest) (*AuthRefreshResponse, error) {
	require.NotNil(s.t, s.authRefresh, "unexpected AuthRefresh call")
	return s.authRefresh(ctx, request)
}

func TestAuthServiceHandlers(t *testing.T) {
	serviceErr := status.Error(codes.Unauthenticated, "invalid credentials")
	for _, tt := range authRPCFixtures() {
		t.Run(tt.name, func(t *testing.T) {
			for _, outcome := range []struct {
				name string
				err  error
			}{
				{name: "success"},
				{name: "service_error", err: serviceErr},
			} {
				t.Run("direct_"+outcome.name, func(t *testing.T) {
					ctx := context.WithValue(t.Context(), authContextKey{}, "direct")
					server := &authServerStub{t: t}
					decodeCalls, serviceCalls := 0, 0
					var decoded any
					tt.setHandler(server, func(gotCtx context.Context, request proto.Message) (proto.Message, error) {
						serviceCalls++
						require.Same(t, ctx, gotCtx)
						require.Same(t, decoded, request)
						require.True(t, proto.Equal(tt.request, request))
						if outcome.err != nil {
							return nil, outcome.err
						}
						return tt.response, nil
					})
					decode := func(request any) error {
						decodeCalls++
						require.IsType(t, tt.request, request)
						decoded = request
						proto.Merge(request.(proto.Message), tt.request)
						return nil
					}

					response, err := tt.handler(server, ctx, decode, nil)
					if outcome.err != nil {
						require.Same(t, outcome.err, err)
						require.Nil(t, response)
					} else {
						require.NoError(t, err)
						require.Same(t, tt.response, response)
					}
					require.Equal(t, 1, decodeCalls)
					require.Equal(t, 1, serviceCalls)
				})

				t.Run("interceptor_forward_"+outcome.name, func(t *testing.T) {
					ctx := context.WithValue(t.Context(), authContextKey{}, "original")
					forwardedCtx := context.WithValue(ctx, authContextKey{}, "intercepted")
					forwardedRequest := tt.request.ProtoReflect().Type().New().Interface()
					server := &authServerStub{t: t}
					decodeCalls, interceptorCalls, serviceCalls := 0, 0, 0
					var decoded any
					tt.setHandler(server, func(gotCtx context.Context, request proto.Message) (proto.Message, error) {
						serviceCalls++
						require.Same(t, forwardedCtx, gotCtx)
						require.Same(t, forwardedRequest, request)
						if outcome.err != nil {
							return nil, outcome.err
						}
						return tt.response, nil
					})
					decode := func(request any) error {
						decodeCalls++
						require.IsType(t, tt.request, request)
						decoded = request
						proto.Merge(request.(proto.Message), tt.request)
						return nil
					}
					interceptor := func(gotCtx context.Context, request any, info *grpc.UnaryServerInfo, next grpc.UnaryHandler) (any, error) {
						interceptorCalls++
						require.Same(t, ctx, gotCtx)
						require.Same(t, decoded, request)
						require.True(t, proto.Equal(tt.request, request.(proto.Message)))
						require.Same(t, server, info.Server)
						require.Equal(t, tt.method, info.FullMethod)
						return next(forwardedCtx, forwardedRequest)
					}

					response, err := tt.handler(server, ctx, decode, interceptor)
					if outcome.err != nil {
						require.Same(t, outcome.err, err)
						require.Nil(t, response)
					} else {
						require.NoError(t, err)
						require.Same(t, tt.response, response)
					}
					require.Equal(t, 1, decodeCalls)
					require.Equal(t, 1, interceptorCalls)
					require.Equal(t, 1, serviceCalls)
				})
			}

			for _, withInterceptor := range []bool{false, true} {
				name := "decode_error_without_interceptor"
				if withInterceptor {
					name = "decode_error_with_interceptor"
				}
				t.Run(name, func(t *testing.T) {
					decodeErr := errors.New("malformed request")
					server := &authServerStub{t: t}
					decodeCalls := 0
					decode := func(request any) error {
						decodeCalls++
						require.IsType(t, tt.request, request)
						return decodeErr
					}
					var interceptor grpc.UnaryServerInterceptor
					if withInterceptor {
						interceptor = func(context.Context, any, *grpc.UnaryServerInfo, grpc.UnaryHandler) (any, error) {
							t.Fatal("interceptor must not run after a decode error")
							return nil, nil
						}
					}

					response, err := tt.handler(server, t.Context(), decode, interceptor)
					require.Same(t, decodeErr, err)
					require.Nil(t, response)
					require.Equal(t, 1, decodeCalls)
				})
			}

			for _, outcome := range []struct {
				name string
				err  error
			}{
				{name: "success"},
				{name: "error", err: status.Error(codes.PermissionDenied, "blocked by interceptor")},
			} {
				t.Run("interceptor_short_circuit_"+outcome.name, func(t *testing.T) {
					ctx := context.WithValue(t.Context(), authContextKey{}, "short circuit")
					server := &authServerStub{t: t}
					decodeCalls, interceptorCalls := 0, 0
					var decoded any
					decode := func(request any) error {
						decodeCalls++
						require.IsType(t, tt.request, request)
						decoded = request
						proto.Merge(request.(proto.Message), tt.request)
						return nil
					}
					interceptor := func(gotCtx context.Context, request any, info *grpc.UnaryServerInfo, _ grpc.UnaryHandler) (any, error) {
						interceptorCalls++
						require.Same(t, ctx, gotCtx)
						require.Same(t, decoded, request)
						require.Same(t, server, info.Server)
						require.Equal(t, tt.method, info.FullMethod)
						if outcome.err != nil {
							return nil, outcome.err
						}
						return tt.response, nil
					}

					response, err := tt.handler(server, ctx, decode, interceptor)
					if outcome.err != nil {
						require.Same(t, outcome.err, err)
						require.Nil(t, response)
					} else {
						require.NoError(t, err)
						require.Same(t, tt.response, response)
					}
					require.Equal(t, 1, decodeCalls)
					require.Equal(t, 1, interceptorCalls)
				})
			}
		})
	}
}

func TestUnimplementedAuthServiceServer(t *testing.T) {
	for _, tt := range authRPCFixtures() {
		t.Run(tt.name, func(t *testing.T) {
			response, err := tt.handler(UnimplementedAuthServiceServer{}, t.Context(), func(any) error { return nil }, nil)
			require.Nil(t, response)
			require.Equal(t, codes.Unimplemented, status.Code(err))
		})
	}
}

type authServerWithNilEmbedding struct {
	*UnimplementedAuthServiceServer
}

func TestRegisterAuthServiceServer(t *testing.T) {
	t.Run("value_embedding", func(t *testing.T) {
		server := grpc.NewServer()
		t.Cleanup(server.Stop)
		RegisterAuthServiceServer(server, &authServerStub{t: t})

		services := server.GetServiceInfo()
		require.Len(t, services, 1)
		info, ok := services["auth.AuthService"]
		require.True(t, ok, "auth service was not registered")
		var methods []string
		for _, method := range info.Methods {
			require.False(t, method.IsClientStream)
			require.False(t, method.IsServerStream)
			methods = append(methods, method.Name)
		}
		require.ElementsMatch(t, []string{"SignIn", "SignUp", "SignOut", "AuthRefresh"}, methods)
	})

	t.Run("nil_pointer_embedding", func(t *testing.T) {
		server := grpc.NewServer()
		t.Cleanup(server.Stop)
		require.Panics(t, func() {
			RegisterAuthServiceServer(server, &authServerWithNilEmbedding{})
		})
		require.Empty(t, server.GetServiceInfo())
	})
}
