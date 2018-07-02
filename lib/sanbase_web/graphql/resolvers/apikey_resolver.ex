defmodule SanbaseWeb.Graphql.Resolvers.ApikeyResolver do
  require Logger

  alias SanbaseWeb.Graphql.Resolvers.Helpers
  alias Sanbase.Auth.{User, Apikey}

  def generate_apikey(_root, _args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    {:ok, _apikey} = Apikey.generate_apikey(user)
    {:ok, user}
  end

  def revoke_apikey(_root, %{apikey: apikey}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    :ok = Apikey.revoke_apikey(user, apikey)

    {:ok, user}
  end

  def apikeys_list(%User{} = user, _args, _resolution) do
    Apikey.apikeys_list(user)
  end
end
