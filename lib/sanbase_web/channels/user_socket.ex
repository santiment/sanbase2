defmodule SanbaseWeb.UserSocket do
  # No `Absinthe.Phoenix.Socket` here: the schema has no GraphQL subscriptions,
  # and GraphQL documents pushed over this socket ran outside the HTTP /graphql
  # pipeline — no auth context, rate limiting, complexity limit or API call
  # export. GraphQL is served over HTTP only.
  use Phoenix.Socket

  import SanbaseWeb.ChannelUtils, only: [params_to_user: 1]

  # User-related channels
  channel("users:*", SanbaseWeb.UserChannel)
  channel("open_restricted_tabs:*", SanbaseWeb.OpenRestrictedTabChannel)
  channel("notifications:*", SanbaseWeb.NotificationsChannel)

  def connect(params, socket)
      when is_map_key(params, "jti") or is_map_key(params, "access_token") do
    with {:ok, user} <- params_to_user(params) do
      {:ok, assign(socket, auth: :user, user_id: user.id, user: user)}
    end
  end

  def connect(_params, socket) do
    {:ok, assign(socket, auth: :none, user_id: nil, user: nil)}
  end

  def id(socket), do: "users_socket:#{socket.assigns.user_id}"
end
