defmodule SanbaseWeb.Graphql.Schema.AuthQueries do
  @moduledoc ~s"""
  Queries and mutations for authentication related intercations
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.AuthResolver

  alias SanbaseWeb.Graphql.Middlewares.{
    JWTAuth,
    DeleteSession,
    CreateOrDeleteSession
  }

  object :auth_queries do
    field :get_active_sessions, list_of(:auth_session) do
      middleware(JWTAuth)
      resolve(&AuthResolver.get_active_sessions/3)
    end
  end

  object :auth_mutations do
    @desc ~s"""
    Destroy the current session and revoke the JWT refresh token. After all
    existing JWT access tokens expire in less than 5 minutes, the existing
    refresh token that is stored in the clients will not be able to generate
    a new access tokens, which will destroy the sessions.
    After this mutation is executed, it will force the authentication process
    to be initiated again in order to obtain new access and refresh tokens.
    """
    field :destroy_session, :boolean do
      middleware(JWTAuth)
      resolve(&AuthResolver.revoke_refresh_token/3)
      middleware(DeleteSession)
    end

    # field :destroy_all_sessions, :boolean do
    # end

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

    field :logout, :logout do
      middleware(JWTAuth, allow_access: true)
      resolve(fn _, _ -> {:ok, %{success: true}} end)
      middleware(CreateOrDeleteSession)
    end
  end
end
