defmodule SanbaseWeb.Graphql.Resolvers.UserTriggerResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Signals.UserTrigger
  alias SanbaseWeb.Graphql.Helpers.Utils

  def triggers(%User{} = user, _args, _resolution) do
    {:ok, UserTrigger.triggers_for(user)}
  end

  def create_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.create_user_trigger(current_user, args)
    |> handle_result("create")
  end

  def update_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.update_user_trigger(current_user, args)
    |> handle_result("update")
  end

  def get_trigger_by_id(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    trigger = UserTrigger.get_trigger_by_id(current_user, args.id)

    {:ok, trigger}
  end

  defp handle_result(result, operation) do
    case result do
      {:ok, ut} ->
        {:ok, ut.trigger}

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
