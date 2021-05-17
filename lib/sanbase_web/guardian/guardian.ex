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

  @access_token_ttl {10, :seconds}
  @refresh_token_ttl {4, :weeks}

  def access_token_ttl(), do: @access_token_ttl

  def get_jwt_tokens(%User{} = user) do
    with {:ok, access_token, _claims} <-
           SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}, ttl: @access_token_ttl),
         {:ok, refresh_token, _claims} <-
           SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt},
             token_type: "refresh",
             ttl: @refresh_token_ttl
           ) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
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

  @doc ~s"""
  Return the resource that is identified by the subject from the claims.
  In this case the subject is a user id.
  """
  @impl Guardian
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
  @impl Guardian
  def after_encode_and_sign(resource, %{"typ" => "refresh"} = claims, token, _options) do
    with {:ok, _} <- Guardian.DB.after_encode_and_sign(resource, claims["typ"], claims, token) do
      {:ok, token}
    end
  end

  def after_encode_and_sign(_resource, _claims, token, _options), do: {:ok, token}

  @impl Guardian
  def on_verify(%{"typ" => "refresh"} = claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_verify(claims, token) do
      {:ok, claims}
    end
  end

  def on_verify(claims, _token, _options), do: {:ok, claims}

  @impl Guardian
  def on_revoke(%{"typ" => "refresh"} = claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_revoke(claims, token) do
      {:ok, claims}
    end
  end

  def on_revoke(claims, _token, _options), do: {:ok, claims}
end
