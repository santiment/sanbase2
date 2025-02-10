defmodule SanbaseWeb.Graphql.Resolvers.UserAffiliateDetailsResolver do
  @moduledoc false
  alias Sanbase.Accounts.User
  alias Sanbase.Affiliate.UserAffiliateDetails

  def are_user_affiliate_datails_submitted(%User{} = user, _, _) do
    {:ok, UserAffiliateDetails.are_user_affiliate_datails_submitted?(user.id)}
  end

  def add_user_affiliate_details(_root, %{telegram_handle: telegram_handle} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    %{
      user_id: current_user.id,
      telegram_handle: telegram_handle,
      marketing_channels: args[:marketing_channels]
    }
    |> UserAffiliateDetails.create()
    |> case do
      {:ok, _} ->
        {:ok, true}

      {:error, error_msg} ->
        {:error, Sanbase.Utils.ErrorHandling.changeset_errors_string(error_msg)}
    end
  end
end
