defmodule Sanbase.Notifications.DiscordBehaviour do
  @moduledoc false
  @callback send_message(webhook :: String.t(), content :: String.t(), opts :: Keyword.t()) ::
              :ok | {:error, term()}
end

defmodule Sanbase.Notifications.DiscordClient do
  @moduledoc false
  @behaviour Sanbase.Notifications.DiscordBehaviour

  def client do
    Application.get_env(:sanbase, :discord_client, __MODULE__)
  end

  @impl Sanbase.Notifications.DiscordBehaviour
  def send_message(webhook, content, opts \\ []) do
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
