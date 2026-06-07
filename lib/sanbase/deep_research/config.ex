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
  """
  @spec run_payload(String.t()) :: map()
  def run_payload(message) when is_binary(message) do
    %{
      assistant_id: assistant_id(),
      input: %{messages: [%{role: "user", content: message}]},
      config: %{configurable: configurable()},
      stream_mode: ["messages", "updates", "custom"],
      stream_subgraphs: true
    }
  end

  @doc "The per-run `configurable` map (only non-nil keys are included)."
  @spec configurable() :: map()
  def configurable() do
    %{
      "search_api" => "tavily",
      "allow_clarification" => get(:allow_clarification, true),
      "max_concurrent_research_units" => get(:max_concurrent_research_units, 2),
      "max_react_tool_calls" => get(:max_react_tool_calls, 500),
      "research_model" => get(:research_model),
      "summarization_model" => get(:summarization_model),
      "compression_model" => get(:compression_model),
      "final_report_model" => get(:final_report_model)
    }
    |> maybe_put_api_keys()
    |> reject_nil_values()
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
