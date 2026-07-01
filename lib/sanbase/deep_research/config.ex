defmodule Sanbase.DeepResearch.Config do
  @moduledoc """
  Configuration + run-payload assembly for the deep research agent.

  Builds the LangGraph run body and the per-run `configurable` overrides.

  The LiveView connects directly to a LangGraph dev server (default
  `http://127.0.0.1:2024`) running the `deep_research_agent` graph. Per-run
  `configurable` overrides are resolved by the agent as
  `configurable` -> env var -> default; so any field we leave unset here falls
  back to the agent server's own `.env` defaults. We therefore only send the
  keys that are explicitly configured on the sanbase side (plus a few static
  safety knobs), never `nil`.

  All values are read from application env under `:sanbase, Sanbase.DeepResearch`,
  populated from system env in `config/runtime.exs`.
  """

  @default_base_url "http://127.0.0.1:2024"
  @default_assistant_id "deep_research_agent"

  @doc "Base URL of the LangGraph server (no trailing slash)."
  @spec base_url() :: String.t()
  def base_url() do
    (get(:base_url) || @default_base_url) |> String.trim_trailing("/")
  end

  @doc "Graph id / assistant id to run."
  @spec assistant_id() :: String.t()
  def assistant_id(), do: get(:assistant_id) || @default_assistant_id

  @doc """
  The full body POSTed to `/threads/:id/runs/stream`.

  Carries `assistant_id`, the user `input.messages`, the per-run
  `config.configurable`, and the multi-channel stream modes that surface the
  typed event protocol (`custom`), state updates (`updates`) and assistant
  thinking tokens (`messages`).

  `opts[:mcp_servers]` is a list of agent MCP server maps
  (`%{"name", "url", "headers", "tools"}`) to connect for this run; when present
  the agent exposes those servers' tools (e.g. Santiment data) to the research.
  `opts[:model_tier]` is the price-tier name picked in the UI (see `model_tiers/0`).
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
      # Models are selected by tier NAME only (extra-low | low | mid | high); the
      # agent ignores per-model keys (research_model etc.) with a warning. The
      # user's UI pick (opts) wins over the deploy-wide default; unset falls back
      # to the agent's own default tier (extra-low).
      "model_tier" => Keyword.get(opts, :model_tier) || get(:model_tier)
    }
    |> maybe_put_api_keys()
    |> maybe_put_mcp(Keyword.get(opts, :mcp_servers, []))
    |> reject_nil_values()
  end

  @doc """
  Tiers selectable in the UI: `{value, label, hint}`. Must mirror `MODEL_TIERS`
  in the agent's `config.py` — the agent warns and falls back to its default on
  an unknown name, so a stale entry degrades gracefully.
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
  Whether the research UI shows the model-tier dropdown
  (`DRA_TIERING_DROPDOWN_ENABLED`, assumed false when missing). Read straight
  from the environment at call time — a feature flag, not app config.
  When false, every run uses the deploy-wide tier (`default_model_tier/0`).
  """
  @spec tiering_dropdown_enabled?() :: boolean()
  def tiering_dropdown_enabled?() do
    System.get_env("DRA_TIERING_DROPDOWN_ENABLED", "false") == "true"
  end

  @doc """
  The catalog of MCP servers the UI can offer. Each entry is
  `%{key, label, url, auth}` (`auth: :user_apikey` resolves to the caller's
  Santiment API key). Configurable via `:mcp_servers` in app env so more
  servers (local or remote) can be added without code changes.
  """
  @spec mcp_catalog() :: [map()]
  def mcp_catalog() do
    case get(:mcp_servers) do
      servers when is_list(servers) and servers != [] -> servers
      _ -> default_mcp_catalog()
    end
  end

  defp default_mcp_catalog() do
    [
      %{
        key: "santiment",
        label: "Santiment",
        url: System.get_env("DRA_MCP_URL", "http://localhost:4000/mcp"),
        auth: :user_apikey
      }
    ]
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

  defp get(key, default \\ nil) do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
