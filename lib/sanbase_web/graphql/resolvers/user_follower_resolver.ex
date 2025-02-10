defmodule SanbaseWeb.Graphql.Resolvers.UserFollowerResolver do
  @moduledoc false
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]

  alias Sanbase.Accounts.UserFollower

  require Logger

  def follow(_root, args, %{context: %{auth: %{auth_method: :user_token, current_user: current_user}}}) do
    args.user_id
    |> to_string()
    |> UserFollower.follow(to_string(current_user.id))
    |> handle_result("follow", current_user)
  end

  def unfollow(_root, args, %{context: %{auth: %{auth_method: :user_token, current_user: current_user}}}) do
    args.user_id
    |> to_string()
    |> UserFollower.unfollow(to_string(current_user.id))
    |> handle_result("unfollow", current_user)
  end

  def following_toggle_notification(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: current_user}}
      }) do
    args.user_id
    |> to_string()
    |> UserFollower.following_toggle_notification(
      to_string(current_user.id),
      args.disable_notifications
    )
    |> handle_result("toggle notifications of", current_user)
  end

  defp handle_result(result, operation, current_user) do
    case result do
      {:ok, _} ->
        {:ok, current_user}

      {:error, error_msg} when is_binary(error_msg) ->
        {:error, error_msg}

      {:error, %Ecto.Changeset{} = changeset} ->
        {
          :error,
          message: "Error trying to #{operation} user", details: changeset_errors(changeset)
        }
    end
  end
end
