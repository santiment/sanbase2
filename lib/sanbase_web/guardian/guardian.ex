defmodule SanbaseWeb.Guardian do
  @moduledoc ~s"""
  Core module for working with JSON Web Token (JWT) authentication.any()

  Glossary:
    - JSON Web Token - JSON web token (JWT), is an open standard (RFC 7519) that
      defines a compact and self-contained way for securely transmitting information
      between parties as a JSON object. Again, JWT is a standard, meaning that all
      JWTs are tokens, but not all tokens are JWTs.


    - claims - JSON web tokens (JWTs) claims are pieces of information asserted
      about a subject. For example, an ID token (which is always a JWT) can contain
      a claim called name that asserts that the name of the user authenticating is
      "John Doe". In a JWT, a claim appears as a name/value pair where the name
      is always a string and the value can be any JSON value. Generally, when we
      talk about a claim in the context of a JWT, we are referring to the name
      (or key).
      In the following example there are 3 claims: sub, name and admin
      ```json
        {
        "sub": "1234567890",
        "name": "John Doe",
        "admin": true
    }
    ```
  """
  use Guardian, otp_app: :sanbase

  alias Sanbase.Accounts.User
  alias Sanbase.Chart.Configuration

  # The shared access token has basically infinite TTL.
  # This is because the shared access tokens should not
  # expire. Their validity is checked by checking their
  # owner's subscription.
  @shared_access_token_ttl {500, :weeks}
  @access_token_ttl {5, :minutes}
  @refresh_token_ttl {4, :weeks}

  def access_token_ttl(), do: @access_token_ttl

  def get_shared_access_token(
        %Configuration.SharedAccessToken{} = struct,
        _opts \\ []
      ) do
    with {:ok, shared_access_token, _claims} <-
           encode_and_sign(struct, %{type: "shared_access_token"}, ttl: @shared_access_token_ttl) do
      {:ok, %{shared_access_token: shared_access_token}}
    end
  end

  def add_jwt_tokens_to_conn_session(conn, jwt_tokens_map) do
    conn
    |> Plug.Conn.put_session(:auth_token, jwt_tokens_map.access_token)
    |> Plug.Conn.put_session(:access_token, jwt_tokens_map.access_token)
    |> Plug.Conn.put_session(:refresh_token, jwt_tokens_map.refresh_token)
  end

  def get_jwt_tokens(%User{} = user, opts \\ []) do
    platform = Keyword.get(opts, :platform, :unknown)
    client = Keyword.get(opts, :client, :unknown)

    with {:ok, access_token, _claims} <-
           encode_and_sign(
             user,
             %{client: client, platform: platform, type: "user_access_token"},
             ttl: @access_token_ttl
           ),
         {:ok, refresh_token, _claims} <-
           encode_and_sign(
             user,
             %{client: client, platform: platform, type: "user_refresh_token"},
             token_type: "refresh",
             ttl: @refresh_token_ttl
           ) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
    end
  end

  def device_data(conn) do
    case List.first(Plug.Conn.get_req_header(conn, "user-agent")) do
      nil ->
        %{platform: :unknown, client: :unknown}

      ua ->
        %{
          platform: Browser.full_platform_name(ua),
          client: Browser.full_browser_name(ua)
        }
    end
  end

  @doc ~s"""
  Return a value identifing the resource that will be used as the `sub` claim.
  It can be any value, but it should be easy to retrieve the resource from the
  token later. Here we choose the user id as it is short and unique.
  """
  @impl Guardian
  def subject_for_token(%User{id: id} = _resource, _claims) do
    {:ok, to_string(id)}
  end

  def subject_for_token(%Configuration.SharedAccessToken{uuid: uuid} = _resource, _claims) do
    {:ok, uuid}
  end

  @doc ~s"""
  Return the resource that is identified by the subject from the claims.
  In this case the subject is a user id.
  """
  @impl Guardian

  def resource_from_claims(%{
        "sub" => shared_access_token_uuid,
        "type" => "shared_access_token"
      }) do
    case Configuration.SharedAccessToken.by_uuid(shared_access_token_uuid) do
      {:ok, token} -> {:ok, token}
      {:error, _} -> {:error, :no_existing_token}
    end
  end

  # TODO: Some time after deploying, change this to also pattern match the type
  # wait some time so all the issues access tokens would have the
  # `type` in their claims.
  def resource_from_claims(%{"sub" => user_id} = _claims) do
    case Sanbase.Accounts.get_user(Sanbase.Math.to_integer(user_id)) do
      {:ok, user} -> {:ok, user}
      {:error, _} -> {:error, :no_existing_user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :no_sub_claim_found}
  end

  def get_config(key) do
    Application.get_env(:sanbase, SanbaseWeb.Endpoint)
    |> Keyword.fetch!(key)
  end

  ##############################################################################
  #### Guardian DB hooks
  ####
  #### The hooks are doing something only for the refresh tokens. The access
  #### tokens are stateless, so no further actions are needed (or could) to
  #### be performed
  ##############################################################################

  @doc ~s"""
  After a refresh token is created and signed, it is stored in the database.

  This is done only for the refresh token while the access token continues to be
  stateless and can be validated without DB calls. The refresh token is only
  accessed when it is exchanged for a new access token, which cannot happen more
  than once per 5 minutes.

  The operation is no-op for access tokens.
  """
  @impl Guardian
  def after_encode_and_sign(resource, %{"typ" => "refresh"} = claims, token, _options) do
    with {:ok, _} <- Guardian.DB.after_encode_and_sign(resource, claims["typ"], claims, token) do
      {:ok, token}
    end
  end

  def after_encode_and_sign(_resource, _claims, token, _options), do: {:ok, token}

  @doc ~s"""
  Verify that a refresh token is present in the database.

  A refresh token is valid if its signature is verified and it is present in the
  database. When a refresh token is revoked it is removed from the database so
  it is immediately invalidated and woudl fail this step.

  The operation is no-op for access tokens.
  """
  @impl Guardian
  def on_verify(%{"typ" => "refresh"} = claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_verify(claims, token) do
      {:ok, claims}
    end
  end

  def on_verify(claims, _token, _options), do: {:ok, claims}

  @doc ~s"""
  Revoke a refresh token by removing it from the database.

  When a refresh token is removed from the database it can no longer be verified
  so it is immediately invalidated.

  The operation is no-op for access tokens.
  """
  @impl Guardian
  def on_revoke(%{"typ" => "refresh"} = claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_revoke(claims, token) do
      {:ok, claims}
    end
  end

  def on_revoke(claims, _token, _options), do: {:ok, claims}

  @doc ~s"""
  When a refresh token is exchanged for an access token update the proper field
  in the database so it can be track how active it is.

  The operation is no-op for access tokens.
  """
  @impl Guardian
  def on_exchange(
        {_, %{"typ" => "refresh"} = claims} = refresh_token_tuple,
        {_, _} = new_access_token,
        _options
      ) do
    {:ok, true} = __MODULE__.Token.refresh_last_exchanged_at(claims)

    {:ok, refresh_token_tuple, new_access_token}
  end

  def on_exchange(old_stuff, new_stuff, _options), do: {:ok, old_stuff, new_stuff}
end
