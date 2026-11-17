defmodule SanbaseWeb.GenericAdmin.UserApikeyToken do
  @moduledoc """
  Admin resource for the tokens backing users' API keys.

  Deleting a row revokes the API key generated from that token: the key is
  derived from the token and a server secret, so without the row the key no
  longer resolves to a user.
  """
  @behaviour SanbaseWeb.GenericAdmin

  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  def schema_module(), do: Sanbase.Accounts.UserApikeyToken
  def resource_name(), do: "user_apikey_tokens"
  def singular_resource_name(), do: "user_apikey_token"

  def resource() do
    %{
      actions: [:delete],
      index_fields: [:id, :user_id, :token, :inserted_at, :updated_at],
      preloads: [:user],
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        }
      }
    }
  end

  @doc """
  Emits the same `:revoke_apikey` event as a user revoking the key themselves,
  so the removal is recorded the same way.
  """
  def after_delete(%Sanbase.Accounts.UserApikeyToken{} = token) do
    emit_event({:ok, token}, :revoke_apikey, %{user: %Sanbase.Accounts.User{id: token.user_id}})
    :ok
  end
end
