defmodule SanbaseWeb.Graphql.Resolvers.UserTriggerResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]

  alias Sanbase.Accounts.User
  alias Sanbase.Alert.{Trigger, UserTrigger}
  alias Sanbase.Telegram

  def triggers(%User{} = user, _args, _resolution) do
    {:ok,
     UserTrigger.triggers_for(user.id)
     |> Enum.map(&transform_user_trigger/1)
     |> Enum.map(& &1.trigger)}
  end

  def public_triggers(%User{} = user, _args, _resolution) do
    public_triggers =
      user.id
      |> UserTrigger.public_triggers_for()
      |> Enum.map(&transform_user_trigger/1)
      |> Enum.map(& &1.trigger)

    {:ok, public_triggers}
  end

  def create_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    do_create_trigger(current_user, args)
  end

  def update_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    with {:ok, %UserTrigger{} = user_trigger} <-
           UserTrigger.get_trigger_by_if_owner(current_user.id, args.id),
         true <- UserTrigger.trigger_not_frozen?(user_trigger) do
      UserTrigger.update_user_trigger(current_user.id, args)
      |> handle_result("update")
    end
  end

  def remove_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.remove_user_trigger(current_user, args.id)
    |> handle_result("remove")
  end

  def last_triggered_datetime(root, _args, _resolution) do
    case root.last_triggered do
      %{} = empty_map when map_size(empty_map) == 0 ->
        {:ok, nil}

      %{} = map ->
        last_triggered =
          map
          |> Map.values()
          |> Enum.map(&Sanbase.DateTimeUtils.from_iso8601!/1)
          |> Enum.max(DateTime)

        {:ok, last_triggered}
    end
  end

  def get_trigger_by_id(_root, %{id: id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case UserTrigger.get_trigger_by_id(current_user.id, id) do
      {:ok, nil} ->
        {:error,
         "Trigger with id #{id} does not exist or it is a private trigger owned by another user."}

      {:ok, trigger} ->
        {:ok, trigger}
    end
    |> handle_result("get by id")
  end

  def get_trigger_by_id(_root, %{id: id}, _resolution) do
    case UserTrigger.get_trigger_by_id(nil, id) do
      {:ok, nil} ->
        {:error,
         "Trigger with id #{id} does not exist or it is a private trigger owned by another user."}

      {:ok, trigger} ->
        {:ok, trigger}
    end
    |> handle_result("get by id")
  end

  def public_triggers_for_user(_root, args, _resolution) do
    public_triggers =
      args.user_id |> UserTrigger.public_triggers_for() |> Enum.map(&transform_user_trigger/1)

    {:ok, public_triggers}
  end

  def all_public_triggers(_root, _args, _resolution) do
    {:ok, UserTrigger.all_public_triggers() |> Enum.map(&transform_user_trigger/1)}
  end

  def historical_trigger_points(_root, args, _) do
    UserTrigger.historical_trigger_points(args)
  end

  def alerts_stats_24h(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    {:ok, Sanbase.Alerts.Stats.fired_alerts_24h(current_user.id)}
  end

  # Private functions

  defp do_create_trigger(current_user, args) do
    UserTrigger.create_user_trigger(current_user, args)
    |> handle_result("create")
    |> case do
      {:ok, result} ->
        Telegram.send_message(
          current_user,
          """
          Successfully created a new alert of type: #{Trigger.human_readable_settings_type(args.settings["type"])}

          Title: #{args.title}#{if args[:description], do: "\nDescription: #{args[:description]}"}

          This bot will send you a message when the alert triggers 🤖
          """
        )

        {:ok, result}

      error ->
        error
    end
  end

  defp handle_result(result, operation) do
    case result do
      {:ok, ut} ->
        {:ok, Sanbase.Repo.preload(ut, :tags) |> transform_user_trigger()}

      {:error, error_msg} when is_binary(error_msg) ->
        {:error, error_msg}

      {:error, %Ecto.Changeset{} = changeset} ->
        {
          :error,
          message: "Cannot #{operation} trigger!", details: changeset_errors(changeset)
        }
    end
  end
end
