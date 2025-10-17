defmodule Sanbase.MCP.MarketPulseCheckPrompt do
  @moduledoc """
  Market Pulse Check - A comprehensive market health analysis prompt

  Performs a comprehensive market health check by:
  1. Start with trending_stories_tool (time_period='1h') to capture immediate sentiment
  2. Identify the top 3 mentioned tokens from related_tokens
  3. For each token, fetch price_usd and volume_usd metrics
  4. Compare current sentiment ratios against 30-day price trends
  5. Summarize whether sentiment is leading or lagging price action

  This gives a quick snapshot of market efficiency and potential opportunities.
  """

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
  end

  @impl true
  def get_messages(_params, frame) do
    content = build_market_pulse_prompt()

    # Create properly structured for MCP: https://hexdocs.pm/anubis_mcp/0.14.0/Anubis.Server.Component.Prompt.html#module-example
    text_content = %{
      "type" => "text",
      "text" => content
    }

    response =
      Response.prompt()
      |> Response.user_message(text_content)

    {:reply, response, frame}
  end

  defp build_market_pulse_prompt do
    """
    # Market Pulse Check Analysis

    Please perform a comprehensive market health check following these steps:

    ## Step 1: Capture Market Sentiment
    Use the **trending_stories_tool** with:
    - time_period: '1h'
    - size: 10

    Analyze the trending stories to understand current market sentiment and narrative.

    ## Step 2: Identify Key Tokens
    From the trending stories response, identify the **top 3 most mentioned tokens** from the related_tokens field.

    ## Step 3: Fetch Token Metrics
    For each of the top 3 tokens, use the **fetch_metric_data_tool** to get:
    - price_usd (30-day historical data)
    - volume_usd (30-day historical data)

    ## Step 4: Cross-Reference Analysis
    Compare current sentiment ratios vs recent price movements and volume patterns.

    ## Step 5: Market Efficiency Summary
    Provide insights on sentiment leading vs lagging price action, opportunities, and risks.

    End your response with: "DYOR"
    """
  end
end
