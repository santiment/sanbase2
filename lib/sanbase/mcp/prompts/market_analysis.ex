defmodule Sanbase.MCP.Prompts.MarketAnalysis do
  @moduledoc """
  MCP prompt for KOLs and analysts to generate structured market analysis content.

  Fetches on-chain activity, exchange flows, social dominance, and price data
  for a given asset, then frames it as a narrative ready for publishing.
  """

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    %{
      slug: {:required, :string},
      time_period: {:string, {:default, "7d"}},
      platform: {:string, {:default, "X/Twitter"}}
    }
  end

  @impl true
  def get_messages(%{slug: slug, time_period: time_period, platform: platform}, frame) do
    message = """
    You are a crypto market analyst preparing a data-driven market analysis thread for #{platform}.

    Using the Santiment MCP tools, fetch the following data for **#{slug}** over the last **#{time_period}**:

    **Price & Market Context:**
    - `price_usd` (interval: 1d)
    - `marketcap_usd` (interval: 1d)
    - `volume_usd` (interval: 1d)

    **On-Chain Activity:**
    - `daily_active_addresses` (interval: 1d)
    - `transactions_count` (interval: 1d)
    - `transaction_volume_usd` (interval: 1d)
    - `network_growth` (interval: 1d)

    **Exchange Flows:**
    - `exchange_inflow_usd` (interval: 1d)
    - `exchange_outflow_usd` (interval: 1d)
    - `supply_on_exchanges` (interval: 1d)

    **Social Data:**
    - `social_dominance_total` (interval: 1d)
    - `social_volume_total` (interval: 1d)
    - `sentiment_weighted_total` (interval: 1d)

    Also fetch the latest trending stories and words using the combined trends tool.

    After gathering all data, produce the analysis in this structure:

    1. **Headline** — one-line summary of the current state
    2. **Price Action** — what happened and key levels
    3. **On-Chain Signal** — is network activity supporting the move?
    4. **Exchange Flow Signal** — accumulation or distribution?
    5. **Social Signal** — crowd sentiment and attention levels
    6. **Conclusion** — data-backed thesis on what comes next

    Format the output as a thread optimized for #{platform}. Cite specific data points with numbers.
    Include a note that data is sourced from Santiment.
    """

    response =
      Response.prompt()
      |> Response.user_message(message)

    {:reply, response, frame}
  end
end
