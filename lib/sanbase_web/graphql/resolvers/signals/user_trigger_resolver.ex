defmodule SanbaseWeb.Graphql.Resolvers.UserTriggerResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [transform_user_trigger: 1]
  alias Sanbase.Auth.User
  alias Sanbase.Signals.{Trigger, UserTrigger}
  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Telegram

  def triggers(%User{} = user, _args, _resolution) do
    {:ok, UserTrigger.triggers_for(user) |> Enum.map(& &1.trigger)}
  end

  def create_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.create_user_trigger(current_user, args)
    |> handle_result("create")
    |> case do
      {:ok, result} ->
        Telegram.send_message(
          current_user,
          "Successfully created a new signal of type: #{
            Trigger.human_readable_settings_type(args.settings["type"])
          }"
        )

        {:ok, result}

      error ->
        error
    end
  end

  def update_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.update_user_trigger(current_user, args)
    |> handle_result("update")
  end

  def remove_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.remove_user_trigger(current_user, args.id)
    |> handle_result("remove")
  end

  def get_trigger_by_id(_root, %{id: id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.get_trigger_by_id(current_user, id)
    |> handle_result("get by id")
  end

  def public_triggers_for_user(_root, args, _resolution) do
    {:ok, UserTrigger.public_triggers_for(args.user_id) |> Enum.map(&transform_user_trigger/1)}
  end

  def all_public_triggers(_root, _args, _resolution) do
    {:ok, UserTrigger.all_public_triggers() |> Enum.map(&transform_user_trigger/1)}
  end

  def historical_trigger_points(_root, args, _) do
    UserTrigger.historical_trigger_points(args)
  end

  defp handle_result(result, operation) do
    case result do
      {:ok, ut} ->
        {:ok, transform_user_trigger(ut)}

      {:error, error_msg} when is_binary(error_msg) ->
        {:error, error_msg}

      {:error, %Ecto.Changeset{} = changeset} ->
        {
          :error,
          message: "Cannot #{operation} trigger!", details: Utils.error_details(changeset)
        }
    end
  end
end
