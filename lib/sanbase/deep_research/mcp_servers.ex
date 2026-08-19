defmodule Sanbase.DeepResearch.McpServers do
  @moduledoc """
  Maps enabled MCP catalog entries (`Sanbase.DeepResearch.Config.mcp_catalog/0`) to
  the server configs the agent expects. Auth is a property of the server, so each
  entry declares its own `:auth`:

    * `:none` — public server, no `Authorization` header.
    * `:santiment_apikey` — `Apikey <key>` from the caller's Santiment key
      (generated on demand) or the entry's `:apikey_override`. Only sanbase's own
      MCP server accepts one, so this mode belongs to that entry alone.
    * `:bearer` — `Bearer <token>` from the entry's `:token`, for a third-party
      server we hold a static credential for.

  An entry is dropped with a warning rather than sent unauthenticated when its
  credential does not resolve, its `:auth` is unimplemented, or it is malformed.
  """

  require Logger

  alias Sanbase.Accounts.{Apikey, User}

  @doc """
  Configs for the `enabled` entries. May create the caller's Santiment API key, so
  call it from the stream task, not from a GenServer callback.
  """
  @spec build([map()], User.t() | nil) :: [map()]
  def build([], _user), do: []

  def build(enabled, user) do
    # One lookup covers every entry (a user has one key), skipped when nothing needs
    # it — resolving one can CREATE a key.
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

  # No credential (an anonymous caller has no key): drop rather than connect open.
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

  # Entries come from `runtime.exs`, so an unset env var can leave `url: nil`. Reading
  # the keys blind would raise inside the stream task, parking the turn `:paused` and
  # making Continue repeat the crash — drop the server and run without it.
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
