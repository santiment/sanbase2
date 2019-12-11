defmodule Sanbase.Intercom do
  @moduledoc """
  Sync all users and user stats into intercom
  """
  import Ecto.Query

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias Sanbase.Billing.Product
  alias Sanbase.Signal.UserTrigger

  @intercom_url "https://api.intercom.io/users"

  def sync_users do
    triggers_map = User.resource_user_count_map(Sanbase.Signal.UserTrigger)
    insights_map = User.resource_user_count_map(Sanbase.Insight.Post)
    watchlists_map = User.resource_user_count_map(Sanbase.UserList)

    User.all()
    |> Stream.map(fn user ->
      fetch_stats_for_user(user, %{
        triggers_map: triggers_map,
        insights_map: insights_map,
        watchlists_map: watchlists_map
      })
    end)
    |> Stream.map(&Jason.encode!/1)
    |> Enum.each(&send_user_stats_to_intercom/1)
  end

  def get_data_for_user(user_id) do
    triggers_map = User.resource_user_count_map(Sanbase.Signal.UserTrigger)
    insights_map = User.resource_user_count_map(Sanbase.Insight.Post)
    watchlists_map = User.resource_user_count_map(Sanbase.UserList)

    Repo.get(User, user_id)
    |> fetch_stats_for_user(%{
      triggers_map: triggers_map,
      insights_map: insights_map,
      watchlists_map: watchlists_map
    })
    |> Jason.encode!()
  end

  defp fetch_stats_for_user(
         %User{
           id: id,
           email: email,
           username: username,
           san_balance: san_balance,
           stripe_customer_id: stripe_customer_id
         } = user,
         %{
           triggers_map: triggers_map,
           insights_map: insights_map,
           watchlists_map: watchlists_map
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
      custom_attributes:
        %{
          all_watchlists_count: Map.get(watchlists_map, id, 0),
          all_triggers_count: Map.get(triggers_map, id, 0),
          all_insights_count: Map.get(insights_map, id, 0),
          staked_san_tokens: format_balance(san_balance),
          sanbase_subscription_current_status: sanbase_subscription_current_status,
          sanbase_trial_created_at: sanbase_trial_created_at,
          user_paid_after_trial: user_paid_after_trial
        }
        |> Map.merge(triggers_type_count(user))
    }

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
      {:ok, customer} ->
        if customer.subscriptions.object == "list" do
          customer.subscriptions.data
          |> Enum.filter(&(&1.plan.product == sanbase_product_stripe_id))
          |> Enum.max_by(& &1.created, fn -> nil end)
          |> case do
            nil -> {nil, nil}
            subscription -> {subscription.status, format_dt(subscription.trial_start)}
          end
        else
          {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end

  def send_user_stats_to_intercom(stats_json) do
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{Config.get(:api_key)}"}
    ]

    HTTPoison.post(@intercom_url, stats_json, headers)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.info("Stats sent: #{inspect(stats_json |> Jason.decode!())}}")
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

  defp format_balance(nil), do: 0.0
  defp format_balance(balance), do: Decimal.to_float(balance)

  defp format_dt(nil), do: nil

  defp format_dt(unix_dt) do
    DateTime.from_unix!(unix_dt)
    |> DateTime.to_iso8601()
  end
end
