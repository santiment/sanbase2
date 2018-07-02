defmodule SanbaseWeb.Graphql.Resolvers.ApikeyResolver do
  require Logger

  alias SanbaseWeb.Graphql.Resolvers.Helpers
  alias Sanbase.Auth.{User, Apikey}

  def generate_apikey(_root, _args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    with {:ok, _apikey} <- Apikey.generate_apikey(user) do
      {:ok, user}
    else
      error -> {:error, "Failed to generate apikey. Inspecting error: #{inspect(error)}"}
    end
  end

  def revoke_apikey(_root, %{apikey: apikey}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    with :ok <- Apikey.revoke_apikey(user, apikey) do
      {:ok, user}
    else
      _error ->
        {:error, "Failed to revoke apikey. Provided apikey is malformed or not valid."}
    end
  end

  def apikeys_list(%User{} = user, _args, _resolution) do
    Apikey.apikeys_list(user)
  end
end
