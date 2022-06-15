defmodule SanbaseWeb.Graphql.Middlewares.Helpers do
  @moduledoc ~s"""
  Common functions used among multiple middlewares
  """

  alias Sanbase.Accounts.User
  alias Absinthe.Resolution

  def allow_access?(_current_user, true), do: true

  def allow_access?(%User{privacy_policy_accepted: privacy_policy_accepted}, allow_access) do
    if allow_access || privacy_policy_accepted do
      true
    else
      {:error, "Access denied. Accept the privacy policy to activate your account."}
    end
  end

  def handle_user_access(current_user, opts, resolution) do
    allow_access = Keyword.get(opts, :allow_access_without_terms_accepted, false)

    case allow_access?(current_user, allow_access) do
      true ->
        resolution

      {:error, _message} = error ->
        resolution
        |> Resolution.put_result(error)
    end
  end
end
