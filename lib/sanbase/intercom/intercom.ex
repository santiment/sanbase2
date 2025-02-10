defmodule Sanbase.Intercom do
  @moduledoc """
  Sync all users and user stats into intercom
  """

  import Ecto.Query
  import Sanbase.Accounts.User.Ecto, only: [is_registered: 0]

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.Statistics
  alias Sanbase.Accounts.User
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Subscription
  alias Sanbase.Clickhouse.ApiCallData
  alias Sanbase.Clickhouse.Query
  alias Sanbase.ClickhouseRepo
  alias Sanbase.Insight.Post
  alias Sanbase.Repo
  alias Sanbase.Utils.Config

  require Logger

  @user_events_url "https://api.intercom.io/events?type=user"
  @contacts_url "https://api.intercom.io/contacts"
  @data_attributes_url "https://api.intercom.io/data_attributes"

  @batch_size 100
  @max_retries 5

  def intercom_to_kafka(all_stats \\ nil) do
    Logger.info("[intercom_to_kafka] Start")
    all_stats = all_stats || all_users_stats()

    process_batch_fn = fn contacts ->
      contacts =
        Enum.reject(contacts, fn c ->
          is_nil(c["external_id"]) or not Regex.match?(~r/^\d+$/, c["external_id"])
        end)

      user_ids = Enum.map(contacts, & &1["external_id"])
      users_map = user_ids |> fetch_users_db() |> Map.new(fn u -> {to_string(u.id), u} end)

      updated_contacts =
        Enum.map(contacts, fn contact ->
          user_id = contact["external_id"]

          if users_map[user_id] do
            stats = fetch_stats_for_user(users_map[user_id], all_stats)
            Map.merge(contact, stats)
          else
            contact
          end
        end)

      # save in kafka
      updated_contacts
      |> Enum.map(fn contact ->
        %{
          user_id: contact["external_id"],
          properties: contact,
          inserted_at: Timex.beginning_of_day(DateTime.utc_now())
        }
      end)
      |> persist_kafka_async()
    end

    if has_intercom_api_key?() do
      fetch_contacts(%{per_page: @batch_size}, process_batch_fn)
    else
      :ok
    end

    Logger.info("[intercom_to_kafka] Finish")
  end

  def sync_newly_registered_to_intercom do
    since = Timex.shift(DateTime.utc_now(), hours: -30)

    if has_intercom_api_key?() do
      sync_newly_registered_to_intercom(since)
    end

    :ok
  end

  def sync_newly_registered_to_intercom(dt) do
    dt
    |> fetch_new_registrations_since()
    |> Enum.each(fn user_id ->
      if is_nil(get_contact_by_user_id(user_id)) do
        create_contact(user_id)
      end
    end)
  end

  def save_contacts_to_intercom(contacts) do
    Enum.each(contacts, fn contact ->
      update_contact(contact["id"], contact)
    end)
  end

  def fetch_new_registrations_since(dt) do
    Repo.all(from(u in User, where: is_registered() and u.inserted_at > ^dt, select: u.id))
  end

  def create_contact(user_id) do
    body = Jason.encode!(%{role: "user", external_id: user_id})

    HTTPoison.post(@contacts_url, body, intercom_headers())
  end

  def create_data_attribute(name, type) do
    body = Jason.encode!(%{name: name, model: "contact", data_type: type})

    HTTPoison.post(@data_attributes_url, body, intercom_headers())
  end

  def list_data_attributes do
    HTTPoison.get(@data_attributes_url <> "?model=contact", intercom_headers())
  end

  def get_contact_by_user_id(user_id) do
    body = Jason.encode!(%{query: %{field: "external_id", operator: "=", value: to_string(user_id)}})

    with {:ok, response} <- HTTPoison.post("#{@contacts_url}/search", body, intercom_headers()) do
      response
      |> Map.get(:body)
      |> Jason.decode!()
      |> Map.get("data")
      |> List.first()
    end
  end

  def update_contact(intercom_id, params) do
    body_json = Jason.encode!(params)

    "#{@contacts_url}/#{intercom_id}"
    |> HTTPoison.put(body_json, intercom_headers())
    |> case do
      {:ok, response} ->
        response

      {:error, reason} ->
        Logger.error("Error updating contact: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_events_for_user(user_id, since \\ nil) do
    url = "#{@user_events_url}&user_id=#{user_id}"
    url = if since, do: "#{url}&since=#{since}", else: url

    fetch_all_events(url)
  end

  def all_users_stats do
    {:ok, users_used_api} = ApiCallData.users_used_api()
    {:ok, users_used_sansheets} = ApiCallData.users_used_sansheets()
    {:ok, api_calls_count_per_user} = ApiCallData.api_calls_count_per_user()
    all_user_subscriptions_map = Subscription.Stats.all_user_subscriptions_map()

    %{
      paid_users: paid_users(),
      triggers_map: Statistics.resource_user_count_map(UserTrigger),
      insights_map: Statistics.resource_user_count_map(Post),
      watchlists_map: Statistics.resource_user_count_map(Sanbase.UserList),
      screeners_map: Statistics.user_screeners_count_map(),
      user_triggers_type_count: Statistics.user_triggers_type_count(),
      users_used_api_list: users_used_api,
      users_used_sansheets_list: users_used_sansheets,
      api_calls_per_user_count: api_calls_count_per_user,
      all_user_subscriptions_map: all_user_subscriptions_map
    }
  end

  def all_users_stats(until) do
    {:ok, users_used_api} = ApiCallData.users_used_api(until: until)
    {:ok, users_used_sansheets} = ApiCallData.users_used_sansheets(until: until)
    {:ok, api_calls_count_per_user} = ApiCallData.api_calls_count_per_user(until: until)

    %{
      paid_users: paid_users(),
      triggers_map: Statistics.resource_user_count_map(UserTrigger),
      insights_map: Statistics.resource_user_count_map(Post),
      watchlists_map: Statistics.resource_user_count_map(Sanbase.UserList),
      screeners_map: Statistics.user_screeners_count_map(),
      user_triggers_type_count: Statistics.user_triggers_type_count(),
      users_used_api_list: users_used_api,
      users_used_sansheets_list: users_used_sansheets,
      api_calls_per_user_count: api_calls_count_per_user,
      all_user_subscriptions_map: Subscription.Stats.all_user_subscriptions_map()
    }
  end

  def fetch_all_db_user_ids do
    Repo.all(from(u in User, order_by: [asc: u.id], select: u.id))
  end

  def fetch_ch_data_user(user_id, date) do
    sql = """
    SELECT dt, user_id, attributes
    FROM sanbase_user_intercom_attributes
    WHERE (toStartOfDay(dt) = {{date}}) AND user_id = {{user_id}}
    """

    params = %{date: date, user_id: user_id}

    query_struct = Query.new(sql, params)

    ClickhouseRepo.query_transform(query_struct, fn [dt, user_id, attributes] ->
      %{
        dt: dt,
        user_id: user_id,
        attributes: Jason.decode!(attributes)
      }
    end)
  end

  def fetch_ch_data(datetime, limit, offset) do
    sql = """
    SELECT dt, user_id, attributes
    FROM sanbase_user_intercom_attributes
    WHERE (toStartOfDay(dt) = {{date}}) AND user_id >= 87180
    ORDER BY user_id ASC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    params = %{
      date: datetime |> DateTime.to_date() |> Date.to_string(),
      limit: limit,
      offset: offset * limit
    }

    query_struct = Query.new(sql, params)

    ClickhouseRepo.query_transform(query_struct, fn [dt, user_id, attributes] ->
      %{
        dt: dt,
        user_id: user_id,
        attributes: Jason.decode!(attributes)
      }
    end)
  end

  def fetch_all_synced_user_ids do
    sql = """
    SELECT user_id
    FROM sanbase_user_intercom_attributes
    WHERE toStartOfDay(dt) = {{date}}
    ORDER BY user_id ASC
    """

    today = DateTime.utc_now() |> DateTime.to_date() |> to_string()
    params = %{date: today}

    query_struct = Query.new(sql, params)

    {:ok, user_ids} = ClickhouseRepo.query_transform(query_struct, fn [user_id] -> user_id end)

    user_ids
  end

  def has_intercom_api_key? do
    apikey = intercom_api_key()
    is_binary(apikey) and apikey != ""
  end

  # helpers

  defp fetch_contacts(args, process_batch_fn) do
    case do_fetch(args) do
      {_, []} ->
        :ok

      {nil, _contacts} ->
        :ok

      {next, contacts} ->
        try do
          process_batch_fn.(contacts)
        rescue
          e ->
            Logger.error("[intercom_to_kafka] error: #{inspect(e)}")
        end

        fetch_contacts(Map.put(args, :starting_after, next), process_batch_fn)
    end
  end

  defp do_fetch(args, attempt \\ 0) do
    params = URI.encode_query(args)
    url = "#{@contacts_url}?#{params}"

    url
    |> HTTPoison.get(intercom_headers())
    |> case do
      {:ok, response} ->
        body =
          response
          |> Map.get(:body)
          |> Jason.decode!()

        Logger.info(
          "[intercom_to_kafka] page=#{body["pages"]["page"]} from total_pages: #{body["pages"]["total_pages"]} | progress=#{round(body["pages"]["page"] / body["pages"]["total_pages"] * 100)}%"
        )

        {body["pages"]["next"]["starting_after"], body["data"]}

      {:error, %HTTPoison.Error{reason: :timeout} = response} ->
        Logger.error("[intercom_to_kafka] #{inspect(response)}")
        Logger.error("[intercom_to_kafka] retrying ... attempt: #{attempt + 1}")

        if attempt <= @max_retries do
          Process.sleep(1000)
          do_fetch(args, attempt + 1)
        end

      {:error, response} ->
        Logger.error("[intercom_to_kafka] #{inspect(response)}")
    end
  end

  def persist_kafka_async(user_attributes) do
    user_attributes
    |> to_json_kv_tuple()
    |> Sanbase.KafkaExporter.persist_async(:sanbase_user_intercom_attributes)
  end

  defp to_json_kv_tuple(user_attributes) do
    Enum.map(user_attributes, fn %{user_id: user_id, properties: attributes, inserted_at: timestamp} ->
      timestamp = DateTime.to_unix(timestamp)
      key = "#{user_id}_#{timestamp}"

      data = %{
        user_id: user_id,
        attributes: attributes |> Map.drop(["email", "name", "phone", "avatar"]) |> Jason.encode!(),
        timestamp: timestamp
      }

      {key, Jason.encode!(data)}
    end)
  end

  defp fetch_stats_for_user(%User{id: id} = user, data) do
    user_paid_with = if id in data.paid_users, do: "fiat", else: "not_paid"
    subs_data = sanbase_subs_data(data.all_user_subscriptions_map[id])

    stats = %{
      "user_id" => id,
      "email" => user.email,
      "name" => user.username,
      "signed_up_at" => signed_up_at(user),
      "custom_attributes" =>
        Map.merge(
          %{
            all_watchlists_count: Map.get(data.watchlists_map, id, 0),
            all_triggers_count: Map.get(data.triggers_map, id, 0),
            all_insights_count: Map.get(data.insights_map, id, 0),
            all_screeners_count: Map.get(data.screeners_map, id, 0),
            staked_san_tokens: san_balance(user),
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
          },
          triggers_type_count(data.user_triggers_type_count[id])
        )
    }

    # email must be dropped if nil so user still can be created in Intercom if doesn't exist
    stats = if user.email, do: stats, else: Map.delete(stats, :email)

    stats
  end

  def san_balance(user) do
    if user.eth_accounts == [] do
      +0.0
    else
      Sanbase.Math.to_float(user.san_balance)
    end
  end

  def sanbase_subs_data(nil) do
    %{
      sanbase_subscription_current_status: nil,
      sanbase_trial_created_at: nil,
      user_paid_after_trial: false,
      active_subscriptions: ""
    }
  end

  def sanbase_subs_data(user_sub_data) do
    sanbase_subscription_current_status =
      user_sub_data
      |> Enum.filter(&(&1.product == 2))
      |> Enum.max_by(& &1.id, fn -> %{} end)
      |> Map.get(:status, nil)

    sanbase_trial_created_at =
      user_sub_data
      |> Enum.filter(&(&1.product == 2))
      |> Enum.min_by(& &1.id, fn -> %{} end)
      |> case do
        %{trial_end: trial_end} when not is_nil(trial_end) -> Timex.shift(trial_end, days: -14)
        %{} -> nil
      end

    user_paid_after_trial =
      sanbase_trial_created_at && sanbase_subscription_current_status == "active"

    active_subscriptions =
      user_sub_data
      |> Enum.filter(&(&1.status in [:active, :past_due]))
      |> Enum.map_join(", ", &Plan.plan_full_name(&1.plan))

    %{
      sanbase_subscription_current_status: sanbase_subscription_current_status,
      sanbase_trial_created_at: sanbase_trial_created_at,
      user_paid_after_trial: user_paid_after_trial,
      active_subscriptions: active_subscriptions
    }
  end

  defp address_balance_map(eth_accounts) do
    Enum.map_join(eth_accounts, " | ", fn eth_account ->
      case EthAccount.san_balance(eth_account) do
        :error -> "#{eth_account.address}=0.0"
        balance -> "#{eth_account.address}=#{Sanbase.Math.to_float(balance)}"
      end
    end)
  end

  def signed_up_at(user) do
    if User.RegistrationState.registration_finished?(user) do
      user.inserted_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    else
      0
    end
  end

  defp triggers_type_count(nil), do: %{}

  defp triggers_type_count(signals) do
    Map.new(signals, fn [_, type, count] -> {"trigger_" <> type, count} end)
  end

  def fetch_users_db(user_ids) do
    Repo.all(from(u in User, where: u.id in ^user_ids, preload: [:eth_accounts]))
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
    url
    |> HTTPoison.get(intercom_headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error("Error fetching intercom events for url: #{url}. Response: #{inspect(response)}")

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
      SELECT dt, user_id, toString(JSONExtractRaw(data, 'status')) AS status
      FROM sanbase_stripe_transactions
      WHERE status = '"succeeded"'
    )
    GROUP BY user_id
    """

    query
    |> Sanbase.ClickhouseRepo.query_transform([], fn [user_id] -> user_id end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> []
    end
  end

  defp intercom_headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{intercom_api_key()}"},
      {"Intercom-Version", "2.5"}
    ]
  end

  defp intercom_api_key do
    Config.module_get(__MODULE__, :api_key)
  end
end
