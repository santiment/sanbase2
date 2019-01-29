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
    {:ok, triggers} = UserTrigger.create_trigger(current_user, args)

    {:ok, triggers}
  end

  def update_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    {:ok, triggers} = UserTrigger.update_trigger(current_user, args)

    {:ok, triggers}
  end

  def get_trigger_by_id(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    trigger = UserTrigger.get_trigger_by_id(current_user, args.id)

    {:ok, trigger}
  end
end
