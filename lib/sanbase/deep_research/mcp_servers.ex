defmodule Sanbase.DeepResearch.McpServers do
  @moduledoc """
  Maps enabled MCP catalog entries (see `Sanbase.DeepResearch.Config.mcp_catalog/0`)
  to the server configs the agent expects.

  Auth is a property of the server, so every entry declares its own `:auth`:

    * `:none` — a public server; no `Authorization` header.
    * `:santiment_apikey` — `Authorization: Apikey <key>` with the caller's
      Santiment API key (generated on demand) or the entry's `:apikey_override`.
      Only sanbase's own MCP server accepts a Santiment key, so this mode belongs
      to that entry alone.
    * `:bearer` — `Authorization: Bearer <token>` with the entry's `:token`, for a
      third-party server we hold a static credential for.

  An entry is dropped (with a warning) rather than sent unauthenticated when its
  credential does not resolve, when its `:auth` is one this module does not
  implement, or when the entry itself is malformed — no `:label`/`:url` strings.
  """

  require Logger

  alias Sanbase.Accounts.{Apikey, User}

  @doc """
  Configs for the `enabled` catalog entries. May read and create the caller's
  Santiment API key, so call it from the stream task, not from a GenServer callback.
  """
  @spec build([map()], User.t() | nil) :: [map()]
  def build([], _user), do: []

  def build(enabled, user) do
    # One lookup covers every entry (a user has one Santiment key), and it is
    # skipped when no entry needs it — resolving one can CREATE a key.
    santiment_key = if Enum.any?(enabled, &needs_santiment_apikey?/1), do: santiment_apikey(user)

    enabled |> Enum.map(&server_config(&1, santiment_key)) |> Enum.reject(&is_nil/1)
  end

  defp needs_santiment_apikey?(%{auth: :santiment_apikey} = server),
    do: is_nil(apikey_override(server))

  defp needs_santiment_apikey?(_server), do: false

  defp santiment_apikey(%User{} = user) do
    case Apikey.apikeys_list(user) do
      {:ok, [apikey | _]} -> apikey
      {:ok, []} -> generate_santiment_apikey(user)
      _ -> nil
    end
  end

  defp santiment_apikey(_no_user), do: nil

  defp generate_santiment_apikey(user) do
    case Apikey.generate_apikey(user) do
      {:ok, apikey} -> apikey
      _ -> nil
    end
  end

  defp server_config(%{auth: :none} = server, _santiment_key), do: base_config(server)

  defp server_config(%{auth: :santiment_apikey} = server, santiment_key),
    do: authenticated(server, "Apikey", apikey_override(server) || santiment_key)

  defp server_config(%{auth: :bearer} = server, _santiment_key),
    do: authenticated(server, "Bearer", Map.get(server, :token))

  defp server_config(server, _santiment_key) do
    Logger.warning(
      "DeepResearch dropping MCP server #{inspect(server[:key])}: " <>
        "unsupported auth #{inspect(server[:auth])}"
    )

    nil
  end

  # No credential (e.g. an anonymous caller has no api key): drop the server
  # instead of connecting to it unauthenticated.
  defp authenticated(_server, _scheme, credential) when credential in [nil, ""], do: nil

  defp authenticated(server, scheme, credential) do
    case base_config(server) do
      nil -> nil
      config -> Map.put(config, "headers", %{"Authorization" => "#{scheme} #{credential}"})
    end
  end

  defp base_config(%{label: label, url: url}) when is_binary(label) and is_binary(url) do
    %{"name" => label, "label" => label, "url" => url, "tools" => []}
  end

  # A catalog entry comes from `runtime.exs`, so it can be malformed (an env var
  # nobody set leaves `url: nil`). Dropping it with a warning keeps the run going
  # without that server; reading the keys blind would raise inside the stream task,
  # which parks the turn `:paused` and makes Continue repeat the same crash.
  defp base_config(server) do
    Logger.warning(
      "DeepResearch dropping MCP server #{inspect(server[:key])}: " <>
        "label and url must both be strings, got #{inspect(Map.take(server, [:label, :url]))}"
    )

    nil
  end

  defp apikey_override(server) do
    case Map.get(server, :apikey_override) do
      override when is_binary(override) and override != "" -> override
      _ -> nil
    end
  end
end
