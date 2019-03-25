defmodule SanbaseWeb.Graphql.Resolvers.UserFollowerResolver do
  require Logger

  alias Sanbase.Following.UserFollower
  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Auth.User

  def follow(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: current_user}}
      }) do
    UserFollower.follow(to_string(args.user_id), to_string(current_user.id))
    |> handle_result("follow", current_user)
  end

  def follow(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end

  def unfollow(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: current_user}}
      }) do
    UserFollower.unfollow(to_string(args.user_id), to_string(current_user.id))
    |> handle_result("unfollow", current_user)
  end

  def unfollow(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end

  defp handle_result(result, operation, current_user) do
    case result do
      {:ok, _} ->
        {:ok, current_user |> Sanbase.Repo.preload([:following, :followers])}

      {:error, error_msg} when is_binary(error_msg) ->
        {:error, error_msg}

      {:error, %Ecto.Changeset{} = changeset} ->
        {
          :error,
          message: "Error trying to #{operation} user", details: Utils.error_details(changeset)
        }
    end
  end
end
