defmodule Sanbase.DeepResearch.Config do
  @moduledoc """
  Configuration and run-payload assembly for the deep research agent (a LangGraph
  server running the `deep_research_agent` graph, default `http://127.0.0.1:2024`).

  Builds the run body and the per-run `configurable` overrides. The agent resolves
  `configurable` -> env var -> default, so anything left unset here falls back to its
  own `.env`; we send only what sanbase configures, never `nil`.

  Values come from app env under `:sanbase, Sanbase.DeepResearch`, populated in
  `config/runtime.exs`. Each default lives in one place: connection knobs in the
  attributes below, deploy-shaped ones (MCP catalog, flags) in `runtime.exs`.
  """

  require Logger

  @default_base_url "http://127.0.0.1:2024"
  @default_assistant_id "deep_research_agent"
  @default_pause_after_disconnect_ms 60_000
  @default_checkpoint_every_ms 10_000
  @default_event_silence_ms :timer.minutes(10)

  @doc "Base URL of the LangGraph server (no trailing slash)."
  @spec base_url() :: String.t()
  def base_url() do
    (get(:base_url) || @default_base_url) |> String.trim_trailing("/")
  end

  @doc "Graph id / assistant id to run."
  @spec assistant_id() :: String.t()
  def assistant_id(), do: get(:assistant_id) || @default_assistant_id

  @doc """
  How long a runner keeps a run alive unwatched: long enough for a websocket
  reconnect, short enough that a closed tab stops burning tokens.
  """
  @spec pause_after_disconnect_ms() :: non_neg_integer()
  def pause_after_disconnect_ms(),
    do: get(:pause_after_disconnect_ms, @default_pause_after_disconnect_ms)

  @doc """
  How often a runner rewrites the row of the turn it is streaming. A killed runner
  (pod eviction, VM kill) loses whatever it has not written, so this trades database
  churn (each write serializes the whole timeline) against how much of an interrupted
  turn survives.
  """
  @spec checkpoint_every_ms() :: non_neg_integer()
  def checkpoint_every_ms(), do: get(:checkpoint_every_ms, @default_checkpoint_every_ms)

  @doc """
  How long a streaming run may go without a single EVENT before the runner asks the
  agent server whether the run is still alive. The stream's own idle timeout never
  fires on a dead run: the server keeps the connection open with heartbeats after a
  run has errored server-side, so without this a turn spins for ever.
  """
  @spec event_silence_ms() :: non_neg_integer()
  def event_silence_ms(), do: get(:event_silence_ms, @default_event_silence_ms)

  @doc """
  Bearer token for every request to the LangGraph server (`DRA_AUTH_TOKEN`). `nil`
  (unset or blank) means no auth header: fine locally, required behind an
  authenticating proxy.
  """
  @spec auth_token() :: String.t() | nil
  def auth_token() do
    case get(:auth_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  @doc """
  The full body POSTed to `/threads/:id/runs/stream`: `assistant_id`, the user
  `input.messages`, the per-run `config.configurable`, and the stream modes that
  surface the typed event protocol (`custom`), state updates (`updates`) and
  thinking tokens (`messages`).

  `opts[:mcp_servers]` are agent MCP server maps
  (`%{"name", "url", "headers", "tools"}`) whose tools the run may use;
  `opts[:model_tier]` is the price tier picked in the UI (see `model_tiers/0`).
  """
  @spec run_payload(String.t(), keyword()) :: map()
  def run_payload(message, opts \\ []) when is_binary(message) do
    %{
      assistant_id: assistant_id(),
      input: %{messages: [%{role: "user", content: message}]},
      config: %{configurable: configurable(opts)},
      stream_mode: ["messages", "updates", "custom"],
      stream_subgraphs: true
    }
  end

  @doc "The per-run `configurable` map (only non-nil keys are included)."
  @spec configurable(keyword()) :: map()
  def configurable(opts \\ []) do
    %{
      "search_api" => "tavily",
      "allow_clarification" => get(:allow_clarification, true),
      "max_concurrent_research_units" => get(:max_concurrent_research_units, 2),
      "max_react_tool_calls" => get(:max_react_tool_calls, 500),
      # Tier NAME only (extra-low | low | mid | high) — the agent warns and ignores
      # per-model keys. UI pick wins over the deploy default; unset falls back to the
      # agent's own.
      "model_tier" => Keyword.get(opts, :model_tier) || get(:model_tier)
    }
    |> maybe_put_api_keys()
    |> maybe_put_mcp(Keyword.get(opts, :mcp_servers, []))
    |> reject_nil_values()
  end

  @doc """
  Tiers selectable in the UI: `{value, label, hint}`. Mirrors `MODEL_TIERS` in the
  agent's `config.py`; an unknown name only degrades to the agent's default.
  """
  @spec model_tiers() :: [{String.t(), String.t(), String.t()}]
  def model_tiers() do
    [
      {"extra-low", "Extra low", "cheapest models — demos and smoke tests"},
      {"low", "Low", "budget models — quick looks"},
      {"mid", "Mid", "balanced cost/quality — everyday research"},
      {"high", "High", "best quality — decision-grade research"}
    ]
  end

  @doc "The tier preselected in the UI: deploy config, else the agent's default."
  @spec default_model_tier() :: String.t()
  def default_model_tier(), do: get(:model_tier) || "extra-low"

  @doc """
  Whether the UI shows the model-tier dropdown (`DRA_TIERING_DROPDOWN_ENABLED`, off
  when unset). Off means every run uses `default_model_tier/0`.
  """
  @spec tiering_dropdown_enabled?() :: boolean()
  def tiering_dropdown_enabled?(), do: get(:tiering_dropdown_enabled, false) == true

  @doc """
  The catalog of MCP servers the UI can offer. Each entry is `%{key, label, url, auth}`,
  where `auth` names how THAT server authenticates — `:none`, `:santiment_apikey`
  (sanbase's own MCP) or `:bearer`; see `Sanbase.DeepResearch.McpServers`. Defined in
  `runtime.exs` under `:mcp_servers`, so servers can be added without code changes; an
  empty or missing list means the UI offers no data sources.

  Entries missing a required key are dropped with a warning — a malformed map handed to
  the LiveView would crash the mount.
  """
  @spec mcp_catalog() :: [map()]
  def mcp_catalog() do
    case get(:mcp_servers) do
      servers when is_list(servers) -> Enum.filter(servers, &valid_mcp_server?/1)
      _ -> []
    end
  end

  defp valid_mcp_server?(%{key: key, label: label, url: url, auth: auth})
       when is_binary(key) and is_binary(label) and is_binary(url) and is_atom(auth),
       do: true

  defp valid_mcp_server?(server) do
    Logger.warning("DeepResearch dropping malformed :mcp_servers entry: #{inspect(server)}")
    false
  end

  defp maybe_put_mcp(configurable, []), do: configurable

  defp maybe_put_mcp(configurable, mcp_servers) when is_list(mcp_servers) do
    configurable
    |> Map.put("mcp_servers", mcp_servers)
    |> Map.put("mcp_prompt", get(:mcp_prompt) || default_mcp_prompt())
  end

  defp default_mcp_prompt() do
    "Use the Santiment tools for quantitative crypto data — on-chain, social and " <>
      "market metrics, asset/metric discovery, insights and trending stories. Prefer " <>
      "them over generic web search for numeric metrics, and cite them in the report."
  end

  defp maybe_put_api_keys(configurable) do
    api_keys =
      %{
        # Not a typo: the agent talks to OpenRouter through an OpenAI-compatible
        # client, which reads the key from `OPENAI_API_KEY`.
        "OPENAI_API_KEY" => get(:openrouter_api_key),
        "TAVILY_API_KEY" => get(:tavily_api_key)
      }
      |> reject_nil_values()

    if map_size(api_keys) > 0 do
      Map.put(configurable, "apiKeys", api_keys)
    else
      configurable
    end
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  # The env namespace is `Sanbase.DeepResearch` (what `runtime.exs` configures), NOT this
  # module: reading `__MODULE__` would ignore every configured value and leave the agent
  # on its compiled-in defaults.
  @env_key Sanbase.DeepResearch

  defp get(key, default \\ nil) do
    :sanbase
    |> Application.get_env(@env_key, [])
    |> Keyword.get(key, default)
  end
end
