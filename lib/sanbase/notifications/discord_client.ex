defmodule Sanbase.Notifications.DiscordBehaviour do
  @callback send_message(webhook :: String.t() | nil, content :: String.t(), opts :: Keyword.t()) ::
              :ok | {:error, :webhook_not_configured | term()}
end

defmodule Sanbase.Notifications.DiscordClient do
  @behaviour Sanbase.Notifications.DiscordBehaviour

  def client do
    Application.get_env(:sanbase, :discord_client, __MODULE__)
  end

  @impl Sanbase.Notifications.DiscordBehaviour
  def send_message(webhook, content, opts \\ [])

  # Req.post/2 raises on a nil url, e.g. when DISCORD_NOTIFICATIONS_WEBHOOK_URL is not set
  def send_message(webhook, _content, _opts) when not is_binary(webhook) or webhook == "",
    do: {:error, :webhook_not_configured}

  def send_message(webhook, content, opts) do
    username = Keyword.get(opts, :username, "Sanbase")
    payload = %{content: content}
    payload = if username, do: Map.put(payload, :username, username), else: payload

    case Req.post(webhook, json: payload) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "Discord API error: status #{status}, body: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end
end
