defmodule Sanbase.Intercom do
  @moduledoc """
  Sync all users and user stats into intercom
  """

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias Sanbase.Billing.Product
  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Clickhouse.ApiCallData
  alias Sanbase.Intercom.UserAttributes

  @intercom_url "https://api.intercom.io/users"

  def all_users_stats do
    %{
      customer_payment_type_map: customer_payment_type_map(),
      triggers_map: User.resource_user_count_map(Sanbase.Signal.UserTrigger),
      insights_map: User.resource_user_count_map(Sanbase.Insight.Post),
      watchlists_map: User.resource_user_count_map(Sanbase.UserList),
      users_used_api_list: ApiCallData.users_used_api(),
      users_used_sansheets_list: ApiCallData.users_used_sansheets(),
      api_calls_per_user_count: ApiCallData.api_calls_count_per_user(),
      users_with_monitored_watchlist:
        Sanbase.UserLists.Statistics.users_with_monitored_watchlist()
        |> Enum.map(fn {%{id: user_id}, count} -> {user_id, count} end)
        |> Enum.into(%{})
    }
  end

  def sync_users do
    # Skip if api key not present in env. (Run only on production)
    all_users_stats = all_users_stats()

    if intercom_api_key() do
      User.all()
      |> Stream.map(fn user ->
        fetch_stats_for_user(user, all_users_stats)
      end)
      |> Enum.each(&send_user_stats_to_intercom/1)
    else
      :ok
    end
  end

  def get_data_for_user(user_id) do
    Repo.get(User, user_id)
    |> fetch_stats_for_user(all_users_stats())
    |> Jason.encode!()
  end

  defp fetch_stats_for_user(
         %User{
           id: id,
           email: email,
           username: username,
           san_balance: san_balance,
           stripe_customer_id: stripe_customer_id,
           inserted_at: inserted_at
         } = user,
         %{
           triggers_map: triggers_map,
           insights_map: insights_map,
           watchlists_map: watchlists_map,
           users_used_api_list: users_used_api_list,
           users_used_sansheets_list: users_used_sansheets_list,
           api_calls_per_user_count: api_calls_per_user_count,
           users_with_monitored_watchlist: users_with_monitored_watchlist,
           customer_payment_type_map: customer_payment_type_map
         }
       ) do
    {sanbase_subscription_current_status, sanbase_trial_created_at} =
      fetch_sanbase_subscription_data(stripe_customer_id)

    user_paid_after_trial =
      sanbase_trial_created_at && sanbase_subscription_current_status == "active"

    stats = %{
      user_id: id,
      email: email,
      name: username,
      signed_up_at: DateTime.from_naive!(inserted_at, "Etc/UTC") |> DateTime.to_unix(),
      custom_attributes:
        %{
          all_watchlists_count: Map.get(watchlists_map, id, 0),
          all_triggers_count: Map.get(triggers_map, id, 0),
          all_insights_count: Map.get(insights_map, id, 0),
          staked_san_tokens: format_balance(san_balance),
          sanbase_subscription_current_status: sanbase_subscription_current_status,
          sanbase_trial_created_at: sanbase_trial_created_at,
          user_paid_after_trial: user_paid_after_trial,
          user_paid_with: Map.get(customer_payment_type_map, stripe_customer_id, "not_paid"),
          weekly_digest:
            Sanbase.Auth.UserSettings.settings_for(user).newsletter_subscription |> to_string(),
          used_sanapi: id in users_used_api_list,
          used_sansheets: id in users_used_sansheets_list,
          api_calls_count: Map.get(api_calls_per_user_count, id, 0),
          weekly_report_watchlist_count: Map.get(users_with_monitored_watchlist, id, 0)
        }
        |> Map.merge(triggers_type_count(user))
    }

    # email must be dropped if nil so user still can be created in Intercom if doesn't exist
    stats =
      unless email do
        Map.delete(stats, :email)
      else
        stats
      end

    stats
  end

  defp triggers_type_count(user) do
    user
    |> UserTrigger.triggers_for()
    |> Enum.group_by(fn ut -> ut.trigger.settings.type end)
    |> Enum.map(fn {type, list} -> {"trigger_" <> type, length(list)} end)
    |> Enum.into(%{})
  end

  defp fetch_sanbase_subscription_data(nil) do
    {nil, nil}
  end

  defp fetch_sanbase_subscription_data(stripe_customer_id) do
    sanbase_product_stripe_id = Product.by_id(Product.product_sanbase()).stripe_id

    Stripe.Customer.retrieve(stripe_customer_id)
    |> case do
      {:ok, %{subscriptions: %{object: "list", data: data}}} when is_list(data) ->
        data
        |> Enum.filter(&(&1.plan.product == sanbase_product_stripe_id))
        |> Enum.max_by(& &1.created, fn -> nil end)
        |> case do
          nil -> {nil, nil}
          subscription -> {subscription.status, format_dt(subscription.trial_start)}
        end

      _ ->
        {nil, nil}
    end
  end

  def send_user_stats_to_intercom(stats) do
    stats_json = Jason.encode!(stats)

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{intercom_api_key()}"}
    ]

    HTTPoison.post(@intercom_url, stats_json, headers)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.info("Stats sent: #{inspect(stats_json |> Jason.decode!())}}")

        UserAttributes.save(%{user_id: stats.user_id, properties: stats})

        :ok

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error(
          "Error sending to intercom stats: #{inspect(stats_json |> Jason.decode!())}}. Response: #{
            inspect(response)
          }"
        )

      {:error, reason} ->
        Logger.error(
          "Error sending to intercom stats: #{inspect(stats_json |> Jason.decode!())}}. Reason: #{
            inspect(reason)
          }"
        )
    end
  end

  # %{"cus_HQ1vCgehxitRJU" => "fiat" | "san", ...}
  def customer_payment_type_map() do
    do_list([], nil)
    |> filter_only_payments()
    |> classify_payments_by_type()
  end

  defp filter_only_payments(invoices) do
    invoices
    |> Enum.filter(&(&1.status == "paid" && &1.total > 0))
    |> Enum.dedup_by(fn %{customer: customer} -> customer end)
  end

  def classify_payments_by_type(invoices) do
    Enum.reduce(invoices, %{}, fn invoice, acc ->
      cond do
        invoice.starting_balance == 0 ->
          Map.put(acc, invoice.customer, "fiat")

        invoice.total == abs(invoice.starting_balance) ->
          Map.put(acc, invoice.customer, "san")

        true ->
          acc
      end
    end)
  end

  def do_list([], nil) do
    list = list_invoices(%{limit: 100})
    do_list(list, Enum.at(list, -1) |> Map.get(:id))
  end

  def do_list(acc, next) do
    case list_invoices(%{limit: 100, starting_after: next}) do
      [] -> acc
      list -> do_list(acc ++ list, Enum.at(list, -1) |> Map.get(:id))
    end
  end

  defp list_invoices(params) do
    Stripe.Invoice.list(params)
    |> elem(1)
    |> Map.get(:data)
    |> Enum.map(fn invoice ->
      Map.split(invoice, [:id, :customer, :total, :starting_balance, :status, :created])
      |> elem(0)
    end)
  end

  defp format_balance(nil), do: 0.0
  defp format_balance(balance), do: Decimal.to_float(balance)

  defp format_dt(nil), do: nil

  defp format_dt(unix_dt) do
    DateTime.from_unix!(unix_dt)
    |> DateTime.to_iso8601()
  end

  defp intercom_api_key() do
    Config.get(:api_key)
  end
end
