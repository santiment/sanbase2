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

  Nightly reconciliation repairs missed billing-event adds for subscriptions
  created on or after `api_business_onboarding_since` (list launch; defaults to
  2026-07-22). Historical Business+ customers from before that cutoff are
  intentionally never backfilled.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.Accounts
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.Email.MailjetApi
  alias Sanbase.Repo
  alias Sanbase.Utils.Config

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
  Add the user's current email to the onboarding list when they have any eligible
  active Business-or-higher API subscription. Used on account email change so the
  new address is enrolled (add-only; the old Mailjet contact is left as-is).
  """
  @spec maybe_add_user(non_neg_integer()) :: :ok | {:error, term()}
  def maybe_add_user(user_id) when is_integer(user_id) do
    if user_has_eligible_subscription?(user_id) do
      add_user_email(user_id)
    else
      :ok
    end
  end

  @doc """
  Whether a subscription qualifies its owner for the onboarding list: an `active`
  subscription on an API-product Business-or-higher plan.
  """
  @spec eligible?(Subscription.t() | nil) :: boolean()
  def eligible?(%Subscription{status: :active, plan: %{} = plan}),
    do: business_or_higher_api_plan?(plan)

  def eligible?(_), do: false

  @doc """
  Distinct emails of users with an eligible subscription inserted on or after the
  configured launch cutoff. Empty list when the cutoff is not configured.
  """
  @spec eligible_user_emails() :: [String.t()]
  def eligible_user_emails do
    case onboarding_since() do
      nil ->
        []

      since ->
        business_names = @business_plan_names

        from(s in Subscription,
          join: p in assoc(s, :plan),
          join: u in assoc(s, :user),
          where: s.status == :active,
          where: s.inserted_at >= ^since,
          where: p.product_id == ^Product.product_api(),
          where: p.name in ^business_names or like(p.name, "CUSTOM%"),
          where: not is_nil(u.email) and u.email != "",
          distinct: true,
          select: u.email
        )
        |> Repo.all()
    end
  end

  @doc """
  Add-only reconciliation against the Mailjet list.

  Subscribes any post-cutoff eligible emails missing from Mailjet. Logs contacts
  present in Mailjet but not in the desired set (report only; never removes).
  """
  @spec reconcile() ::
          %{
            added: non_neg_integer(),
            missing_emails: [String.t()],
            extra_count: non_neg_integer()
          }
          | {:error, term()}
  def reconcile do
    case onboarding_since() do
      nil ->
        Logger.info(
          "[ApiBusinessOnboardingList] Skipping reconcile: api_business_onboarding_since is not configured."
        )

        %{added: 0, missing_emails: [], extra_count: 0}

      _since ->
        do_reconcile()
    end
  end

  defp do_reconcile do
    desired = MapSet.new(eligible_user_emails())

    case MailjetApi.client().fetch_list_emails(@list_atom) do
      {:ok, current_emails} ->
        current = MapSet.new(current_emails)
        missing = MapSet.difference(desired, current) |> MapSet.to_list()
        extras = MapSet.difference(current, desired)
        extra_count = MapSet.size(extras)

        result =
          case missing do
            [] ->
              :ok

            emails ->
              MailjetApi.client().subscribe(@list_atom, emails)
          end

        case result do
          :ok ->
            Logger.info(
              "[ApiBusinessOnboardingList] Reconcile complete. added=#{length(missing)} extra_count=#{extra_count}"
            )

            if extra_count > 0 do
              Logger.info(
                "[ApiBusinessOnboardingList] Mailjet members not in desired set (sample): #{inspect(Enum.take(MapSet.to_list(extras), 20))}"
              )
            end

            %{added: length(missing), missing_emails: missing, extra_count: extra_count}

          {:error, reason} = error ->
            Logger.error(
              "[ApiBusinessOnboardingList] Reconcile failed while subscribing missing contacts: #{inspect(reason)}"
            )

            error
        end

      {:error, :list_not_configured} ->
        Logger.info(
          "[ApiBusinessOnboardingList] Skipping reconcile: onboarding list is not configured."
        )

        %{added: 0, missing_emails: [], extra_count: 0}

      {:error, reason} = error ->
        Logger.error(
          "[ApiBusinessOnboardingList] Reconcile failed fetching Mailjet list: #{inspect(reason)}"
        )

        error
    end
  end

  defp user_has_eligible_subscription?(user_id) do
    case onboarding_since() do
      nil ->
        false

      since ->
        from(s in Subscription,
          join: p in assoc(s, :plan),
          where: s.user_id == ^user_id,
          where: s.status == :active,
          where: s.inserted_at >= ^since,
          where: p.product_id == ^Product.product_api(),
          where: p.name in ^@business_plan_names or like(p.name, "CUSTOM%"),
          select: s.id,
          limit: 1
        )
        |> Repo.exists?()
    end
  end

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

  defp onboarding_since do
    case Config.module_get(__MODULE__, :api_business_onboarding_since, nil) do
      %NaiveDateTime{} = ndt ->
        NaiveDateTime.truncate(ndt, :second)

      %DateTime{} = dt ->
        DateTime.to_naive(DateTime.truncate(dt, :second))

      value when is_binary(value) and value != "" ->
        parse_since(value)

      _ ->
        nil
    end
  end

  defp parse_since(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} ->
        DateTime.to_naive(DateTime.truncate(dt, :second))

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} ->
            NaiveDateTime.truncate(ndt, :second)

          {:error, _} ->
            Logger.warning(
              "[ApiBusinessOnboardingList] Invalid api_business_onboarding_since=#{inspect(value)}; ignoring."
            )

            nil
        end
    end
  end
end
