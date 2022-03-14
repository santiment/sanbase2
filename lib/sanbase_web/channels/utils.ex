defmodule SanbaseWeb.ChannelUtils do
  alias Sanbase.Accounts.User

  def params_to_user(%{"access_token" => jwt}), do: jwt_to_user(jwt)
  def params_to_user(%{"jti" => jti}), do: jti_to_user(jti)
  def params_to_user(_), do: {:error, "Params must contain jti or access_token keys"}

  # Private functions

  defp jti_to_user(jti) do
    case SanbaseWeb.Guardian.Token.user_by_jti(jti) do
      {:ok, %User{} = user} ->
        {:ok, user}

      _ ->
        {:error, %{reason: "Invalid JTI of a JWT"}}
    end
  end

  defp jwt_to_user(jwt) do
    case SanbaseWeb.Guardian.resource_from_token(jwt) do
      {:ok, %User{} = user, _} ->
        {:ok, user}

      {:error, :token_expired} ->
        {:error, %{reason: "Token Expired"}}

      {:error, :invalid_token} ->
        {:error, %{reason: "Invalid token"}}

      _ ->
        {:error, %{reason: "Invalid JSON Web Token (JWT)"}}
    end
  end
end
