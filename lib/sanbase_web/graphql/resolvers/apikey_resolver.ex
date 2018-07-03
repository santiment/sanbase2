defmodule SanbaseWeb.Graphql.Resolvers.ApikeyResolver do
  @moduledoc ~s"""
  Module with resolvers connected to the Apikey authentication. All the logic
  is delegated to the `Apikey` module
  """

  require Logger

  alias Sanbase.Auth.{Apikey, User}

  @doc ~s"""
  Generates an apikey for the given user and returns the `user` struct.
  To fetch all apikeys use the `apikeys` field of the `user` GQL type.
  """
  def generate_apikey(_root, _args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    with {:ok, _apikey} <- Apikey.generate_apikey(user) do
      {:ok, user}
    else
      error ->
        Logger.error("#{inspect(error)}")

        {:error, "Failed to generate apikey."}
    end
  end

  @doc ~s"""
  Revokes an apikey and returns the `user` struct. To fetch all apikeys use the
  `apikeys` field of the `user` GQL type.
  """
  def revoke_apikey(_root, %{apikey: apikey}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    with :ok <- Apikey.revoke_apikey(user, apikey) do
      {:ok, user}
    else
      error ->
        Logger.info("#{inspect(error)}")

        {:error, "Failed to revoke apikey. Provided apikey is malformed or not valid."}
    end
  end

  @doc ~s"""
  Returns a list of all apikeys for the currently JWT authenticated user.
  """
  def apikeys_list(%User{} = user, _args, _resolution) do
    Apikey.apikeys_list(user)
  end
end
