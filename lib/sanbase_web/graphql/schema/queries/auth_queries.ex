defmodule SanbaseWeb.Graphql.Schema.AuthQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.AuthResolver

  alias SanbaseWeb.Graphql.Middlewares.{
    CreateOrDeleteSession,
    DeleteSession,
    JWTAuth,
    RefreshTokenAgeCheck
  }

  object :auth_queries do
    field :get_auth_sessions, list_of(:auth_session) do
      meta(access: :free)
      middleware(JWTAuth)
      resolve(&AuthResolver.get_auth_sessions/3)
    end
  end

  object :auth_mutations do
    @desc ~s"""
    Destroy the current session, revoke the JWT refresh token and remove the
    access and refresh tokens from the sessions.
    After all existing JWT access tokens expire in less than 5 minutes, the existing
    refresh token that is stored in the other clients clients will not be able to
    generate a new access token, which will destroy the sessions.
    After this mutation is executed, it will force the authentication process
    to be initiated again in order to obtain new access and refresh tokens.
    """
    field :destroy_current_session, :boolean do
      middleware(JWTAuth)
      resolve(&AuthResolver.revoke_current_refresh_token/3)
      middleware(DeleteSession)
    end

    @desc ~s"""
    Destroy a session represented by its refresh token jti.
    After all existing JWT access tokens, generated by this refresh token, expire,
    the refresh token that is stored in the clients will not be able to generate
    a new access token, which will destroy the sessions.

    As this API is destroying not the current refresh token but others, for security
    reasons the user must have been authenticated less than 10 minutes ago. This
    will reduce the window in which an attacker can obtain another user's refresh
    token and use it to log that user out.
    """
    field :destroy_session, :boolean do
      arg(:refresh_token_jti, non_null(:string))

      middleware(JWTAuth)
      middleware(RefreshTokenAgeCheck, less_than: "10m")
      resolve(&AuthResolver.revoke_refresh_token/3)
    end

    @desc ~s"""
    Destroy all session represented owned by the owner of the current session.

    After all existing JWT access tokens, generated by any of the refresh tokens
    revoked, expire, the refresh token that is stored in the clients will not be
    able to generate a new access token, which will destroy the sessions.

    As this API is destroying not only the current refresh token but also others,
    for security reasons the user must have been authenticated less than
    10 minutes ago. This will reduce the window in which an attacker can obtain
    another user's refresh token and use it to log that user out.
    """
    field :destroy_all_sessions, :boolean do
      middleware(JWTAuth)
      middleware(RefreshTokenAgeCheck, less_than: "10m")
      resolve(&AuthResolver.revoke_all_refresh_tokens/3)
      middleware(DeleteSession)
    end

    @desc ~s"""
    Login using metamask
    """
    field :eth_login, :login do
      arg(:signature, non_null(:string))
      arg(:address, non_null(:string))
      arg(:message_hash, non_null(:string))

      resolve(&AuthResolver.eth_login/3)
      middleware(CreateOrDeleteSession)
    end

    @desc ~s"""
    Initiate email login. An email with a link that needs to be followed is sent
    to the given email. The sent link has a limited time window in which it is
    valid and can be used only once.
    Some mail clients visit the links in the mail for preview and this could
    invalidate the link
    """
    field :email_login, :email_login_request do
      arg(:email, non_null(:string))
      arg(:username, :string)
      arg(:consent, :string)
      arg(:subscribe_to_weekly_newsletter, :boolean)

      resolve(&AuthResolver.email_login/2)
    end

    @desc ~s"""
    Verifies the email login. This mutation does the actual login.
    """
    field :email_login_verify, :login do
      arg(:email, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&AuthResolver.email_login_verify/2)
      middleware(CreateOrDeleteSession)
    end

    @desc ~s"""
    Delete the current session without revoking the refresh token.
    """
    field :logout, :logout do
      middleware(JWTAuth, allow_access_without_terms_accepted: true)

      resolve(fn root, args, res ->
        {:ok, true} = AuthResolver.revoke_current_refresh_token(root, args, res)

        {:ok, %{success: true}}
      end)

      middleware(CreateOrDeleteSession)
    end
  end
end
