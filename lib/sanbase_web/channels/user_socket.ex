defmodule SanbaseWeb.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: SanbaseWeb.Graphql.Schema

  import SanbaseWeb.ChannelUtils, only: [params_to_user: 1]

  # User-related channels
  channel("users:*", SanbaseWeb.UserChannel)
  channel("user_activities:*", SanbaseWeb.UserActivityChannel)
  channel("open_restricted_tabs:*", SanbaseWeb.OpenRestrictedTabChannel)

  # Metrics-related channels
  channel("metrics:*", SanbaseWeb.MetricChannel)

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
