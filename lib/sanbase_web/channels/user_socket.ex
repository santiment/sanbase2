defmodule SanbaseWeb.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: SanbaseWeb.Graphql.Schema

  import SanbaseWeb.ChannelUtils, only: [params_to_user: 1]

  channel("users:*", SanbaseWeb.UserChannel)
  channel("open_restricted_tabs:*", SanbaseWeb.OpenRestrictedTabChannel)

  def connect(params, socket) do
    with {:ok, user} <- params_to_user(params) do
      {:ok, assign(socket, user_id: user.id, user: user)}
    end
  end

  def id(socket), do: "users_socket:#{socket.assigns.user_id}"
end
