defmodule SanbaseWeb.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: SanbaseWeb.Graphql.Schema

  alias Sanbase.Accounts.User

  channel("users:*", SanbaseWeb.UserChannel)

  ## Channels
  # channel "room:*", SanbaseWeb.RoomChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  def connect(params, socket) do
    with {:ok, user} <- jwt_to_user(params["access_token"]) do
      {:ok, assign(socket, user_id: user.id, user: user)}
    end
  end

  def id(socket), do: "users_socket:#{socket.assigns.user_id}"

  # Private functions

  defp jwt_to_user(jwt) do
    case SanbaseWeb.Guardian.resource_from_token(jwt) do
      {:ok, %User{} = user, _} ->
        {:ok, user}

      {:error, :token_expired} ->
        {:error, %{reason: "Token Expired"}}

      {:error, :invalid_token} ->
        {:error, %{reason: "Invalid token"}}

      _ ->
        {:error, %{reason: "Invalid JSON Web Token (JWT)"}}
    end
  end
end
