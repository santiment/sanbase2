defmodule Sanbase.Intercom do
  @moduledoc """
  Sync all users and user stats into intercom
  """

  import Ecto.Query

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Accounts.{User, Statistics}
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Clickhouse.ApiCallData
  alias Sanbase.Intercom.UserAttributes
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Repo

  @intercom_url "https://api.intercom.io/users"
  @user_events_url "https://api.intercom.io/events?type=user"
  @users_page_size 100

  def all_users_stats do
    %{
      customer_payment_type_map: customer_payment_type_map(),
      triggers_map: Statistics.resource_user_count_map(Sanbase.Alert.UserTrigger),
      insights_map: Statistics.resource_user_count_map(Sanbase.Insight.Post),
      watchlists_map: Statistics.resource_user_count_map(Sanbase.UserList),
      screeners_map: Statistics.user_screeners_count_map(),
      users_used_api_list: ApiCallData.users_used_api(),
      users_used_sansheets_list: ApiCallData.users_used_sansheets(),
      api_calls_per_user_count: ApiCallData.api_calls_count_per_user(),
      user_active_subscriptions_map: Subscription.Stats.user_active_subscriptions_map(),
      users_with_monitored_watchlist:
        Sanbase.UserLists.Statistics.users_with_monitored_watchlist()
        |> Enum.map(fn {%{id: user_id}, count} -> {user_id, count} end)
        |> Enum.into(%{})
    }
  end

  def sync_users do
    Logger.info("Start sync_users to Intercom")

    # Skip if api key not present in env. (Run only on production)
    all_users_stats = all_users_stats()

    if intercom_api_key() do
      1..user_pages()
      |> Stream.flat_map(fn page ->
        users_by_page(page, @users_page_size)
      end)
      |> fetch_and_send_stats(all_users_stats)

      Logger.info("Finish sync_users to Intercom")
    else
      :ok
    end
  end

  defp all_users_count() do
    Repo.one(from(u in User, select: count(u.id)))
  end

  def get_events_for_user(user_id, since \\ nil) do
    url = "#{@user_events_url}&user_id=#{user_id}"
    url = if since, do: "#{url}&since=#{since}", else: url

    fetch_all_events(url)
  end

  def intercom_api_key() do
    Config.get(:api_key)
  end

  # helpers

  defp fetch_stats_for_user(
         %User{
           id: id,
           email: email,
           username: username,
           san_balance: san_balance,
           eth_accounts: eth_accounts,
           stripe_customer_id: stripe_customer_id,
           inserted_at: inserted_at
         } = user,
         %{
           triggers_map: triggers_map,
           insights_map: insights_map,
           watchlists_map: watchlists_map,
           screeners_map: screeners_map,
           users_used_api_list: users_used_api_list,
           users_used_sansheets_list: users_used_sansheets_list,
           api_calls_per_user_count: api_calls_per_user_count,
           users_with_monitored_watchlist: users_with_monitored_watchlist,
           customer_payment_type_map: customer_payment_type_map,
           user_active_subscriptions_map: user_active_subscriptions_map
         }
       ) do
    {sanbase_subscription_current_status, sanbase_trial_created_at} =
      fetch_sanbase_subscription_data(stripe_customer_id)

    user_paid_after_trial =
      sanbase_trial_created_at && sanbase_subscription_current_status == "active"

    address_balance_map =
      eth_accounts
      |> Enum.map(fn eth_account ->
        case EthAccount.san_balance(eth_account) do
          :error -> "#{eth_account.address}=0.0"
          balance -> "#{eth_account.address}=#{Sanbase.Math.to_float(balance)}"
        end
      end)
      |> Enum.join(" | ")

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
          all_screeners_count: Map.get(screeners_map, id, 0),
          staked_san_tokens: Sanbase.Math.to_float(san_balance),
          address_balance_map: address_balance_map,
          sanbase_subscription_current_status: sanbase_subscription_current_status,
          sanbase_trial_created_at: sanbase_trial_created_at,
          user_paid_after_trial: user_paid_after_trial,
          user_paid_with: Map.get(customer_payment_type_map, stripe_customer_id, "not_paid"),
          weekly_digest:
            Sanbase.Accounts.UserSettings.settings_for(user).newsletter_subscription
            |> to_string(),
          used_sanapi: id in users_used_api_list,
          used_sansheets: id in users_used_sansheets_list,
          api_calls_count: Map.get(api_calls_per_user_count, id, 0),
          weekly_report_watchlist_count: Map.get(users_with_monitored_watchlist, id, 0),
          active_subscriptions: Map.get(user_active_subscriptions_map, id, "")
        }
        |> Map.merge(triggers_type_count(user))
    }

    # email must be dropped if nil so user still can be created in Intercom if doesn't exist
    stats = if email, do: stats, else: Map.delete(stats, :email)

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

  defp send_user_stats_to_intercom(stats) do
    stats_json = Jason.encode!(stats)

    HTTPoison.post(@intercom_url, stats_json, intercom_headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.info("Stats sent: #{inspect(stats_json |> Jason.decode!())}}")
        stats = merge_intercom_attributes(stats, body)
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

  defp user_pages() do
    (all_users_count() / @users_page_size)
    |> Float.ceil()
    |> round()
  end

  defp users_by_page(page, page_size) do
    offset = (page - 1) * page_size

    from(u in User,
      order_by: u.id,
      limit: ^page_size,
      offset: ^offset,
      preload: [:eth_accounts]
    )
    |> Repo.all()
  end

  defp fetch_and_send_stats(users, all_users_stats) do
    users
    |> Stream.map(fn user ->
      fetch_stats_for_user(user, all_users_stats)
    end)
    |> Enum.each(&send_user_stats_to_intercom/1)
  end

  defp merge_intercom_attributes(stats, intercom_resp) do
    res = Jason.decode!(intercom_resp)
    app_version = get_in(res, ["custom_attributes", "app_version"])

    if app_version do
      put_in(stats, [:custom_attributes, :app_version], app_version)
    else
      stats
    end
  end

  defp fetch_all_events(url, all_events \\ []) do
    case fetch_events(url) do
      {:ok, %{"events" => []}} ->
        all_events

      {:ok, %{"events" => events, "pages" => %{"next" => next}}} ->
        fetch_all_events(next, all_events ++ events)

      {:ok, %{"events" => events}} ->
        all_events ++ events

      {:error, _} ->
        all_events
    end
  end

  defp fetch_events(url) do
    HTTPoison.get(url, intercom_headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error(
          "Error fetching intercom events for url: #{url}. Response: #{inspect(response)}"
        )

        {:error, response}

      {:error, reason} ->
        Logger.error("Error fetching intercom events for url: #{url}. Reason: #{inspect(reason)}")
        {:error, reason}
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
          Map.put(acc, invoice.customer, "san/crypto")

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
    |> Map.get(:data, [])
    |> Enum.map(fn invoice ->
      Map.split(invoice, [:id, :customer, :total, :starting_balance, :status, :created])
      |> elem(0)
    end)
  end

  defp format_dt(unix_timestmap) when is_integer(unix_timestmap) do
    DateTime.from_unix!(unix_timestmap)
    |> DateTime.to_iso8601()
  end

  defp format_dt(nil), do: nil

  defp intercom_headers() do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{intercom_api_key()}"}
    ]
  end
end
