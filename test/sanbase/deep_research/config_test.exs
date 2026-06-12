defmodule Sanbase.DeepResearch.ConfigTest do
  # Not async: every test rewrites the app env for Sanbase.DeepResearch.
  use ExUnit.Case, async: false

  alias Sanbase.DeepResearch.Config

  setup do
    original = Application.get_env(:sanbase, Sanbase.DeepResearch)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:sanbase, Sanbase.DeepResearch)
        env -> Application.put_env(:sanbase, Sanbase.DeepResearch, env)
      end
    end)

    :ok
  end

  defp put_env(keyword), do: Application.put_env(:sanbase, Sanbase.DeepResearch, keyword)

  describe "base_url/0" do
    test "falls back to the module default when unset" do
      put_env([])
      assert Config.base_url() == "http://127.0.0.1:2024"
    end

    test "an unset (nil) key falls back too — runtime.exs sets nil for a missing env var" do
      put_env(base_url: nil)
      assert Config.base_url() == "http://127.0.0.1:2024"
    end

    test "strips a trailing slash so path joins never double up" do
      put_env(base_url: "https://agent.example.com/")
      assert Config.base_url() == "https://agent.example.com"
    end
  end

  describe "assistant_id/0" do
    test "defaults to the graph name" do
      put_env(assistant_id: nil)
      assert Config.assistant_id() == "deep_research_agent"
    end

    test "is overridable" do
      put_env(assistant_id: "other_graph")
      assert Config.assistant_id() == "other_graph"
    end
  end

  describe "run_payload/2" do
    test "wraps the message and requests all three stream channels" do
      put_env([])
      payload = Config.run_payload("compare eth and sol")

      assert payload.assistant_id == "deep_research_agent"
      assert payload.input == %{messages: [%{role: "user", content: "compare eth and sol"}]}
      assert payload.stream_subgraphs == true
      # `custom` carries the typed event protocol, `updates` state, `messages` thinking.
      assert Enum.sort(payload.stream_mode) == ["custom", "messages", "updates"]
      assert is_map(payload.config.configurable)
    end
  end

  describe "configurable/1" do
    test "nil and empty values are dropped, never sent to the agent" do
      # The agent resolves configurable -> env -> default, so sending a nil would
      # override its own default with nothing.
      put_env(model_tier: nil, openrouter_api_key: "", tavily_api_key: nil)
      configurable = Config.configurable()

      refute Map.has_key?(configurable, "model_tier")
      refute Map.has_key?(configurable, "apiKeys")
      assert configurable["search_api"] == "tavily"
    end

    test "static defaults are present when nothing is configured" do
      put_env([])
      configurable = Config.configurable()

      assert configurable["allow_clarification"] == true
      assert configurable["max_concurrent_research_units"] == 2
      assert configurable["max_react_tool_calls"] == 500
    end

    test "configured knobs override the static defaults" do
      put_env(allow_clarification: false, max_concurrent_research_units: 5)
      configurable = Config.configurable()

      assert configurable["allow_clarification"] == false
      assert configurable["max_concurrent_research_units"] == 5
    end

    test "the per-run model_tier wins over the deploy-wide one" do
      put_env(model_tier: "extra-low")
      assert Config.configurable(model_tier: "high")["model_tier"] == "high"
    end

    test "the deploy-wide model_tier is used when the run does not pick one" do
      put_env(model_tier: "mid")
      assert Config.configurable()["model_tier"] == "mid"
    end

    test "api keys are nested under apiKeys, with only the ones that are set" do
      put_env(openrouter_api_key: "or-key")
      # OPENAI_API_KEY is not a typo — the agent reaches OpenRouter through an
      # OpenAI-compatible client.
      assert Config.configurable()["apiKeys"] == %{"OPENAI_API_KEY" => "or-key"}
    end

    test "no mcp keys are sent when no servers are enabled" do
      put_env([])
      configurable = Config.configurable(mcp_servers: [])

      refute Map.has_key?(configurable, "mcp_servers")
      refute Map.has_key?(configurable, "mcp_prompt")
    end

    test "enabled mcp servers come with a prompt telling the agent to use them" do
      put_env([])
      servers = [%{"name" => "Santiment", "url" => "http://localhost:8000/mcp", "tools" => []}]
      configurable = Config.configurable(mcp_servers: servers)

      assert configurable["mcp_servers"] == servers
      assert configurable["mcp_prompt"] =~ "Santiment"
    end

    test "the mcp prompt is overridable from config" do
      put_env(mcp_prompt: "custom prompt")
      servers = [%{"name" => "Santiment", "url" => "http://x/mcp", "tools" => []}]

      assert Config.configurable(mcp_servers: servers)["mcp_prompt"] == "custom prompt"
    end
  end

  describe "model tiers" do
    test "default_model_tier/0 falls back to the agent's own default" do
      put_env(model_tier: nil)
      assert Config.default_model_tier() == "extra-low"
    end

    test "default_model_tier/0 honours the deploy config" do
      put_env(model_tier: "high")
      assert Config.default_model_tier() == "high"
    end

    test "every UI tier value is a known tier name" do
      # A stale value here degrades to the agent's default with a warning, so keep
      # the list honest.
      values = Enum.map(Config.model_tiers(), fn {value, _label, _hint} -> value end)
      assert values == ["extra-low", "low", "mid", "high"]
    end
  end

  describe "tiering_dropdown_enabled?/0" do
    test "is off unless explicitly true" do
      put_env([])
      refute Config.tiering_dropdown_enabled?()

      put_env(tiering_dropdown_enabled: nil)
      refute Config.tiering_dropdown_enabled?()

      put_env(tiering_dropdown_enabled: "true")
      refute Config.tiering_dropdown_enabled?()
    end

    test "is on for the boolean true" do
      put_env(tiering_dropdown_enabled: true)
      assert Config.tiering_dropdown_enabled?()
    end
  end

  describe "mcp_catalog/0" do
    test "an unset or non-list catalog means no data sources are offered" do
      put_env([])
      assert Config.mcp_catalog() == []

      put_env(mcp_servers: nil)
      assert Config.mcp_catalog() == []
    end

    test "the configured list is returned as-is" do
      catalog = [%{key: "santiment", label: "Santiment", url: "http://x/mcp", auth: :user_apikey}]
      put_env(mcp_servers: catalog)
      assert Config.mcp_catalog() == catalog
    end
  end
end
