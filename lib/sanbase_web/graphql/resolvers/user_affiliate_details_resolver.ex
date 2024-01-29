defmodule SanbaseWeb.Graphql.Resolvers.UserAffiliateDetailsResolver do
  alias Sanbase.Affiliate.UserAffiliateDetails
  alias Sanbase.Accounts.User

  def are_user_affiliate_datails_submitted(%User{} = user, _, _) do
    {:ok, UserAffiliateDetails.are_user_affiliate_datails_submitted?(user.id)}
  end

  def add_user_affiliate_details(
        _root,
        %{telegram_handle: telegram_handle, marketing_channels: marketing_channels},
        %{context: %{auth: %{current_user: current_user}}}
      ) do
    UserAffiliateDetails.create(%{
      user_id: current_user.id,
      telegram_handle: telegram_handle,
      marketing_channels: marketing_channels
    })
    |> case do
      {:ok, _} ->
        {:ok, true}

      {:error, error_msg} ->
        {:error, Sanbase.Utils.ErrorHandling.changeset_errors_string(error_msg)}
    end
  end
end
