defmodule Sanbase.Email.ApiBusinessOnboardingList do
  @moduledoc """
  Keeps a Mailjet contact list populated with the email addresses of users who
  buy an API "Business or higher" subscription - `BUSINESS_PRO`, `BUSINESS_MAX`
  or a `CUSTOM` enterprise plan. Product uses that list to trigger the API-client
  onboarding email.

  Membership is add-only and driven purely by subscription state. There is no
  dedicated account setting - the onboarding email is part of the purchase and
  users opt out via the unsubscribe link in the email itself. Mailjet remembers
  a link-unsubscribe per list and our `subscribe/2` uses the `addnoforce` action,
  so re-running the sync can never resurrect a contact who opted out.

  Only `active` subscriptions qualify (Business+ plans are not offered as trials).
  """

  require Logger

  alias Sanbase.Accounts
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Email.MailjetApi

  @list_atom :api_business_onboarding
  @business_plan_names ["BUSINESS_PRO", "BUSINESS_MAX"]

  @doc "The Mailjet list atom, as registered in `Sanbase.Email.MailjetApi`."
  @spec list_atom() :: atom()
  def list_atom(), do: @list_atom

  @doc """
  Add the subscription owner's email to the onboarding list when the subscription
  is an active API Business-or-higher plan. No-op for anything else. Safe to call
  repeatedly and safe to call with `nil` (e.g. when a subscription cannot be found).
  """
  @spec maybe_add(Subscription.t() | nil) :: :ok | {:error, term()}
  def maybe_add(%Subscription{} = subscription) do
    if eligible?(subscription) do
      add_user_email(subscription.user_id)
    else
      :ok
    end
  end

  def maybe_add(_), do: :ok

  @doc """
  Whether a subscription qualifies its owner for the onboarding list: an `active`
  subscription on an API-product Business-or-higher plan.
  """
  @spec eligible?(Subscription.t() | nil) :: boolean()
  def eligible?(%Subscription{status: :active, plan: %{} = plan}),
    do: business_or_higher_api_plan?(plan)

  def eligible?(_), do: false

  defp business_or_higher_api_plan?(%{product_id: product_id, name: name})
       when is_binary(name) do
    product_id == Product.product_api() and
      (name in @business_plan_names or String.starts_with?(name, "CUSTOM"))
  end

  defp business_or_higher_api_plan?(_), do: false

  defp add_user_email(user_id) do
    case Accounts.get_user(user_id) do
      {:ok, %{email: email}} when is_binary(email) and email != "" ->
        MailjetApi.client().subscribe(@list_atom, email)

      _ ->
        Logger.info(
          "[ApiBusinessOnboardingList] User #{inspect(user_id)} has no email; not adding to the onboarding list."
        )

        :ok
    end
  end
end
