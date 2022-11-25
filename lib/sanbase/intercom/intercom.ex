defmodule Sanbase.Intercom do
  @moduledoc """
  Sync all users and user stats into intercom
  """

  import Ecto.Query

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Accounts.{User, Statistics}
  alias Sanbase.Billing.{Subscription, Product, Plan}
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Clickhouse.ApiCallData
  alias Sanbase.Intercom.UserAttributes
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Repo
  alias Sanbase.ClickhouseRepo

  @intercom_url "https://api.intercom.io/users"
  @user_events_url "https://api.intercom.io/events?type=user"
  @contacts_url "https://api.intercom.io/contacts"
  @users_page_size 100

  def user_stats(user) do
    fetch_stats_for_user(user, all_users_stats())
  end

  def sync_sanbase_to_intercom do
    Logger.info("Start sync_sanbase_to_intercom to Intercom")

    # Skip if api key not present in env. (Run only on production)
    all_users_stats = all_users_stats()

    if has_intercom_api_key?() do
      1..user_pages()
      |> Stream.flat_map(fn page ->
        users_by_page(page, @users_page_size)
      end)
      |> fetch_and_send_stats(all_users_stats)

      Logger.info("Finish sync_sanbase_to_intercom to Intercom")
    else
      :ok
    end
  end

  def sync_intercom_to_kafka do
    if has_intercom_api_key?() do
      Logger.info("Start sync_intercom_to_kafka")

      remaining_user_ids = fetch_all_db_user_ids() -- fetch_all_synced_user_ids()
      Logger.info("Start sync_intercom_to_kafka remaining_user_ids=#{length(remaining_user_ids)}")

      remaining_user_ids
      |> Enum.each(fn user_id ->
        try do
          attributes = get_user(user_id)

          if attributes do
            %{user_id: user_id, properties: attributes, inserted_at: Timex.now()}
            |> UserAttributes.persist_kafka_sync()
          end
        rescue
          e ->
            Logger.error(
              "Error sync_intercom_to_kafka for user: #{user_id}, error: #{inspect(e)}"
            )
        end
      end)

      Logger.info("Finish sync_intercom_to_kafka")
    else
      :ok
    end
  end

  def get_user(user_id) do
    body =
      %{
        query: %{
          field: "external_id",
          operator: "=",
          value: user_id |> to_string()
        }
      }
      |> Jason.encode!()

    HTTPoison.post!(
      "#{@contacts_url}/search",
      body,
      intercom_headers() ++ [{"Intercom-Version", "2.5"}]
    )
    |> Map.get(:body)
    |> Jason.decode!()
    |> Map.get("data")
    |> List.first()
  end

  def update_user(intercom_id, params) do
    body_json = Jason.encode!(params)

    HTTPoison.put!(
      "#{@contacts_url}/#{intercom_id}",
      body_json,
      intercom_headers() ++ [{"Intercom-Version", "2.5"}]
    )
    |> Map.get(:body)
    |> Jason.decode!()
  end

  def get_many_users() do
    body =
      HTTPoison.get!(
        "#{@contacts_url}?per_page=1",
        intercom_headers() ++ [{"Intercom-Version", "2.5"}]
      )
      |> Map.get(:body)
      |> Jason.decode!()

    # data = body["data"]
    # starting_after = body["pages"]["starting_after"]
  end

  def all_users_stats do
    %{
      paid_users: paid_users(),
      triggers_map: Statistics.resource_user_count_map(Sanbase.Alert.UserTrigger),
      insights_map: Statistics.resource_user_count_map(Sanbase.Insight.Post),
      watchlists_map: Statistics.resource_user_count_map(Sanbase.UserList),
      screeners_map: Statistics.user_screeners_count_map(),
      users_used_api_list: ApiCallData.users_used_api(),
      users_used_sansheets_list: ApiCallData.users_used_sansheets(),
      api_calls_per_user_count: ApiCallData.api_calls_count_per_user(),
      all_user_subscriptions_map: Subscription.Stats.all_user_subscriptions_map()
    }
  end

  def fetch_all_db_user_ids() do
    from(u in User, order_by: [asc: u.id], select: u.id)
    |> Repo.all()
  end

  def fetch_all_synced_user_ids() do
    query = """
    SELECT user_id
    FROM sanbase_user_intercom_attributes
    WHERE toStartOfDay(dt) = ?1
    ORDER BY user_id ASC
    """

    today = DateTime.to_date(DateTime.utc_now()) |> to_string

    {:ok, user_ids} = ClickhouseRepo.query_transform(query, [today], fn [user_id] -> user_id end)

    user_ids
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

  def has_intercom_api_key?() do
    apikey = intercom_api_key()
    is_binary(apikey) and apikey != ""
  end

  # helpers

  defp fetch_stats_for_user(%User{id: id} = user, data) do
    user_paid_with = if id in data.paid_users, do: "fiat", else: "not_paid"
    subs_data = sanbase_subs_data(data.all_user_subscriptions_map[id])

    stats = %{
      user_id: id,
      email: user.email,
      name: user.username,
      signed_up_at: signed_up_at(user),
      custom_attributes:
        %{
          all_watchlists_count: Map.get(data.watchlists_map, id, 0),
          all_triggers_count: Map.get(data.triggers_map, id, 0),
          all_insights_count: Map.get(data.insights_map, id, 0),
          all_screeners_count: Map.get(data.screeners_map, id, 0),
          staked_san_tokens: Sanbase.Math.to_float(user.san_balance),
          address_balance_map: address_balance_map(user.eth_accounts),
          used_sanapi: id in data.users_used_api_list,
          used_sansheets: id in data.users_used_sansheets_list,
          api_calls_count: Map.get(data.api_calls_per_user_count, id, 0),
          weekly_report_watchlist_count: 0,
          sanbase_subscription_current_status: subs_data.sanbase_subscription_current_status,
          sanbase_trial_created_at: subs_data.sanbase_trial_created_at,
          user_paid_after_trial: subs_data.user_paid_after_trial,
          active_subscriptions: subs_data.active_subscriptions,
          user_paid_with: user_paid_with
        }
        |> Map.merge(triggers_type_count(user))
    }

    # email must be dropped if nil so user still can be created in Intercom if doesn't exist
    stats = if user.email, do: stats, else: Map.delete(stats, :email)

    stats
  end

  def sanbase_subs_data(user_sub_data) do
    sanbase_subscription_current_status =
      Enum.filter(user_sub_data, &(&1.product == 2))
      |> Enum.max_by(& &1.id, fn -> %{} end)
      |> Map.get(:status, nil)

    sanbase_trial_created_at =
      Enum.filter(user_sub_data, &(&1.product == 2))
      |> Enum.min_by(& &1.id, fn -> %{} end)
      |> case do
        %{trial_end: trial_end} when not is_nil(trial_end) -> Timex.shift(trial_end, days: -14)
        %{} -> nil
      end

    user_paid_after_trial =
      sanbase_trial_created_at && sanbase_subscription_current_status == "active"

    active_subscriptions =
      Enum.map(user_sub_data, &Plan.plan_full_name(&1.plan)) |> Enum.join(", ")

    %{
      sanbase_subscription_current_status: sanbase_subscription_current_status,
      sanbase_trial_created_at: sanbase_trial_created_at,
      user_paid_after_trial: user_paid_after_trial,
      active_subscriptions: active_subscriptions
    }
  end

  defp address_balance_map(eth_accounts) do
    eth_accounts
    |> Enum.map(fn eth_account ->
      case EthAccount.san_balance(eth_account) do
        :error -> "#{eth_account.address}=0.0"
        balance -> "#{eth_account.address}=#{Sanbase.Math.to_float(balance)}"
      end
    end)
    |> Enum.join(" | ")
  end

  def signed_up_at(user) do
    case user.is_registered do
      true -> DateTime.from_naive!(user.inserted_at, "Etc/UTC") |> DateTime.to_unix()
      false -> 0
    end
  end

  defp triggers_type_count(user) do
    user.id
    |> UserTrigger.triggers_for()
    |> Enum.group_by(fn ut -> ut.trigger.settings.type end)
    |> Enum.map(fn {type, list} -> {"trigger_" <> type, length(list)} end)
    |> Enum.into(%{})
  end

  defp send_user_stats_to_intercom(stats) do
    stats_json = Jason.encode!(stats)

    HTTPoison.post(@intercom_url, stats_json, intercom_headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.info("Stats sent for user: #{stats.user_id}}")
        stats = merge_intercom_attributes(stats, body)
        UserAttributes.save(%{user_id: stats.user_id, properties: stats})
        :ok

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error(
          "Error sending to intercom stats: #{inspect(stats)}. Response: #{inspect(response)}"
        )

      {:error, reason} ->
        Logger.error(
          "Error sending to intercom stats: #{inspect(stats)}. Reason: #{inspect(reason)}"
        )
    end
  end

  defp user_pages() do
    (all_users_count() / @users_page_size)
    |> Float.ceil()
    |> round()
  end

  defp users_by_page(page, page_size) do
    {limit, offset} =
      Sanbase.Utils.Transform.opts_to_limit_offset(page: page, page_size: page_size)

    from(u in User,
      order_by: u.id,
      limit: ^limit,
      offset: ^offset,
      preload: [:eth_accounts]
    )
    |> Repo.all()
  end

  defp fetch_and_send_stats(users, all_users_stats) do
    users
    |> Stream.map(fn user ->
      try do
        fetch_stats_for_user(user, all_users_stats)
      rescue
        e ->
          Logger.error(
            "Error sync_sanbase_to_intercom to Intercom (fetch_stats_for_user) for user: #{user.id}, error: #{inspect(e)}"
          )

          reraise e, __STACKTRACE__
      end
    end)
    |> Enum.each(fn user_stats ->
      try do
        send_user_stats_to_intercom(user_stats)
      rescue
        e ->
          Logger.error(
            "Error sync_sanbase_to_intercom to Intercom (send_user_stats_to_intercom) for user: #{user_stats.user_id}, error: #{inspect(e)}"
          )
      end
    end)
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

  def paid_users do
    query = """
    SELECT distinct(user_id)
    FROM (
      SELECT dt, user_id, toString(JSONExtractRaw(data, 'status')) AS status,
      FROM sanbase_stripe_transactions
      WHERE status = '"succeeded"'
    )
    GROUP BY user_id;
    """

    Sanbase.ClickhouseRepo.query_transform(query, [], fn [user_id] -> user_id end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> []
    end
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
