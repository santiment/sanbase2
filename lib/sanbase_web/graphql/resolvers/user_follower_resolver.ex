defmodule SanbaseWeb.Graphql.Resolvers.UserFollowerResolver do
  require Logger

  alias Sanbase.Following.UserFollower

  def follow(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    UserFollower.follow(user.id, args.follower_id)
    {:ok, true}
  end

  def follow(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end

  def unfollow(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    UserFollower.unfollow(user.id, args.follower_id)
    {:ok, true}
  end

  def unfollow(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end
end
