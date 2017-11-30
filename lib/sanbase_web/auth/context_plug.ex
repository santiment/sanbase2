defmodule SanbaseWeb.Auth.ContextPlug do
  @behavior Plug

  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _) do
    context = build_context(conn)
    put_private(conn, :absinthe, %{context: context})
  end

  defp build_context(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
    {:ok, current_user} <- authorize(token) do
      %{current_user: current_user}
    else
      _ -> %{}
    end
  end

  defp authorize(token) do
    with {:ok, user, claims} <- SanbaseWeb.Guardian.resource_from_token(token) do
      {:ok, user}
    else
      _ ->
        Logger.warn("Invalid token in request: #{token}")
        {:error, :invalid_token}
    end
  end
end
