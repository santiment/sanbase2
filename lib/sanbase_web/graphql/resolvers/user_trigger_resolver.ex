defmodule SanbaseWeb.Graphql.Resolvers.UserTriggerResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Signals.UserTrigger
  alias SanbaseWeb.Graphql.Helpers.Utils

  def triggers(%User{} = user, _args, _resolution) do
    {:ok, UserTrigger.triggers_for(user) |> Enum.map(& &1.trigger)}
  end

  def create_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.create_user_trigger(current_user, args)
    |> handle_result("create")
  end

  @spec update_trigger(any(), map(), %{context: %{auth: %{current_user: map()}}}) ::
          {:error, binary() | [{:details, map()} | {:message, <<_::64, _::_*8>>}, ...]}
          | {:ok, Sanbase.Signals.UserTrigger.t()}
  def update_trigger(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserTrigger.update_user_trigger(current_user, args)
    |> handle_result("update")
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

  # Hide the implementation details that `tags` are field of the UserTrigger module
  # Present them as a field of the `trigger` GQL type instead of `user_trigger`
  defp transform_user_trigger(%UserTrigger{trigger: trigger, tags: tags} = ut) do
    ut = Map.from_struct(ut)
    trigger = Map.from_struct(trigger)

    %{
      ut
      | trigger: Map.put(trigger, :tags, tags)
    }
  end
end
