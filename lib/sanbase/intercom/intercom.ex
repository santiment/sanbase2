defmodule Sanbase.Intercom do
  @moduledoc """
  Sync all users and user stats into intercom
  """

  import Ecto.Query

  alias Sanbase.Utils.Config
  alias Sanbase.Accounts.{User, Statistics}
  alias Sanbase.Billing.{Subscription, Plan}
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Clickhouse.ApiCallData
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Repo
  alias Sanbase.ClickhouseRepo

  require Logger

  @user_events_url "https://api.intercom.io/events?type=user"
  @contacts_url "https://api.intercom.io/contacts"

  @batch_size 100
  @max_retries 5

  def intercom_to_kafka(all_stats \\ nil) do
    Logger.info("[intercom_to_kafka] Start")
    all_stats = all_stats || all_users_stats()

    process_batch_fn = fn contacts ->
      contacts =
        contacts
        |> Enum.reject(fn c ->
          is_nil(c["external_id"]) or not Regex.match?(~r/^\d+$/, c["external_id"])
        end)

      user_ids = contacts |> Enum.map(& &1["external_id"])
      users_map = fetch_users_db(user_ids) |> Enum.into(%{}, fn u -> {to_string(u.id), u} end)

      updated_contacts =
        contacts
        |> Enum.map(fn contact ->
          user_id = contact["external_id"]

          if users_map[user_id] do
            stats = fetch_stats_for_user(users_map[user_id], all_stats)
            Map.merge(contact, stats)
          else
            contact
          end
        end)

      # save in kafka
      Enum.map(updated_contacts, fn contact ->
        %{
          user_id: contact["external_id"],
          properties: contact,
          inserted_at: Timex.beginning_of_day(Timex.now())
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

  def fix_old_data(from, to) do
    Logger.info("[fix_old_data] Start")

    for date <- Sanbase.DateTimeUtils.generate_dates_inclusive(from, to) do
      Logger.info("[fix_old_data] Start #{date}")
      datetime = Sanbase.DateTimeUtils.date_to_datetime(date)
      all_stats = all_users_stats(datetime)

      for offset <- 0..25 do
        {:ok, data} = fetch_ch_data(datetime, 1000, offset)

        if data != [] do
          user_ids = data |> Enum.map(& &1[:user_id])
          users_map = fetch_users_db(user_ids) |> Enum.into(%{}, fn u -> {u.id, u} end)

          new_data =
            Enum.map(data, fn %{user_id: user_id, dt: dt, attributes: attributes} ->
              if attributes["custom_attributes"]["used_sanapi"] == nil do
                if users_map[user_id] do
                  stats = fetch_stats_for_user(users_map[user_id], all_stats)
                  custom_attributes = stats["custom_attributes"]
                  attributes = Map.put(attributes, "custom_attributes", custom_attributes)

                  %{
                    user_id: user_id,
                    properties: attributes,
                    inserted_at: DateTime.from_naive!(dt, "Etc/UTC")
                  }
                else
                  nil
                end
              else
                nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          Logger.info("[fix_old_data] date=#{date} rows to save: #{length(new_data)}")
          persist_kafka_async(new_data)
        end
      end

      Logger.info("[fix_old_data] Finish #{date}")
    end

    Logger.info("[fix_old_data] Finish")
  end

  def save_contacts_to_intercom(contacts) do
    contacts
    |> Enum.each(fn contact ->
      update_contact(contact["id"], contact)
    end)
  end

  def get_contact_by_user_id(user_id) do
    body =
      %{
        query: %{
          field: "external_id",
          operator: "=",
          value: user_id |> to_string()
        }
      }
      |> Jason.encode!()

    HTTPoison.post!("#{@contacts_url}/search", body, intercom_headers())
    |> Map.get(:body)
    |> Jason.decode!()
    |> Map.get("data")
    |> List.first()
  end

  def update_contact(intercom_id, params) do
    body_json = Jason.encode!(params)

    HTTPoison.put!("#{@contacts_url}/#{intercom_id}", body_json, intercom_headers())
  end

  def get_events_for_user(user_id, since \\ nil) do
    url = "#{@user_events_url}&user_id=#{user_id}"
    url = if since, do: "#{url}&since=#{since}", else: url

    fetch_all_events(url)
  end

  def all_users_stats do
    %{
      paid_users: paid_users(),
      triggers_map: Statistics.resource_user_count_map(Sanbase.Alert.UserTrigger),
      insights_map: Statistics.resource_user_count_map(Sanbase.Insight.Post),
      watchlists_map: Statistics.resource_user_count_map(Sanbase.UserList),
      screeners_map: Statistics.user_screeners_count_map(),
      user_triggers_type_count: Statistics.user_triggers_type_count(),
      users_used_api_list: ApiCallData.users_used_api(),
      users_used_sansheets_list: ApiCallData.users_used_sansheets(),
      api_calls_per_user_count: ApiCallData.api_calls_count_per_user(),
      all_user_subscriptions_map: Subscription.Stats.all_user_subscriptions_map()
    }
  end

  def all_users_stats(until) do
    %{
      paid_users: paid_users(),
      triggers_map: Statistics.resource_user_count_map(Sanbase.Alert.UserTrigger),
      insights_map: Statistics.resource_user_count_map(Sanbase.Insight.Post),
      watchlists_map: Statistics.resource_user_count_map(Sanbase.UserList),
      screeners_map: Statistics.user_screeners_count_map(),
      user_triggers_type_count: Statistics.user_triggers_type_count(),
      users_used_api_list: ApiCallData.users_used_api(until: until),
      users_used_sansheets_list: ApiCallData.users_used_sansheets(until: until),
      api_calls_per_user_count: ApiCallData.api_calls_count_per_user(until: until),
      all_user_subscriptions_map: Subscription.Stats.all_user_subscriptions_map()
    }
  end

  def fetch_all_db_user_ids() do
    from(u in User, order_by: [asc: u.id], select: u.id)
    |> Repo.all()
  end

  def fetch_ch_data_user(user_id, date) do
    query = """
    SELECT dt, user_id, attributes
    FROM sanbase_user_intercom_attributes
    WHERE (toStartOfDay(dt) = ?1) AND user_id = ?2
    """

    ClickhouseRepo.query_transform(query, [date, user_id], fn [dt, user_id, attributes] ->
      %{
        dt: dt,
        user_id: user_id,
        attributes: Jason.decode!(attributes)
      }
    end)
  end

  def fetch_ch_data(datetime, limit, offset) do
    date = DateTime.to_date(datetime) |> Date.to_string()

    offset = offset * limit

    query = """
    SELECT dt, user_id, attributes
    FROM sanbase_user_intercom_attributes
    WHERE (toStartOfDay(dt) = ?1) AND user_id >= 87180
    ORDER BY user_id ASC
    LIMIT ?2
    OFFSET ?3
    """

    ClickhouseRepo.query_transform(query, [date, limit, offset], fn [dt, user_id, attributes] ->
      %{
        dt: dt,
        user_id: user_id,
        attributes: Jason.decode!(attributes)
      }
    end)
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

  def has_intercom_api_key?() do
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

    HTTPoison.get(url, intercom_headers())
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
    user_attributes
    |> Enum.map(fn %{user_id: user_id, properties: attributes, inserted_at: timestamp} ->
      timestamp = DateTime.to_unix(timestamp)
      key = "#{user_id}_#{timestamp}"

      data = %{
        user_id: user_id,
        attributes: Map.drop(attributes, ["email", "name", "phone", "avatar"]) |> Jason.encode!(),
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
        }
        |> Map.merge(triggers_type_count(data.user_triggers_type_count[id]))
    }

    # email must be dropped if nil so user still can be created in Intercom if doesn't exist
    stats = if user.email, do: stats, else: Map.delete(stats, :email)

    stats
  end

  def san_balance(user) do
    if user.eth_accounts != [] do
      Sanbase.Math.to_float(user.san_balance)
    else
      0.0
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
      user_sub_data
      |> Enum.filter(&(&1.status in [:active, :past_due]))
      |> Enum.map(&Plan.plan_full_name(&1.plan))
      |> Enum.join(", ")

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

  defp triggers_type_count(nil), do: %{}

  defp triggers_type_count(signals) do
    signals
    |> Enum.into(%{}, fn [_, type, count] -> {"trigger_" <> type, count} end)
  end

  def fetch_users_db(user_ids) do
    from(u in User, where: u.id in ^user_ids, preload: [:eth_accounts])
    |> Repo.all()
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
      SELECT dt, user_id, toString(JSONExtractRaw(data, 'status')) AS status
      FROM sanbase_stripe_transactions
      WHERE status = '"succeeded"'
    )
    GROUP BY user_id
    """

    Sanbase.ClickhouseRepo.query_transform(query, [], fn [user_id] -> user_id end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> []
    end
  end

  defp intercom_headers() do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{intercom_api_key()}"},
      {"Intercom-Version", "2.5"}
    ]
  end

  defp intercom_api_key() do
    Config.module_get(__MODULE__, :api_key)
  end
end
