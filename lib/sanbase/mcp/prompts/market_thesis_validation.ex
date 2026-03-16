defmodule Sanbase.MCP.Prompts.MarketThesisValidation do
  @moduledoc """
  MCP prompt for expert traders to validate a market thesis using on-chain
  divergence detection.

  Fetches whale accumulation data, exchange netflow, funding rates, and sentiment
  to confirm or kill a trader's thesis with hard data.
  """

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    %{
      slug: {:required, :string},
      time_period: {:string, {:default, "45d"}},
      thesis: {:required, :string}
    }
  end

  @impl true
  def get_messages(%{slug: slug, time_period: time_period, thesis: thesis}, frame) do
    message = """
    You are an expert crypto analyst validating a trader's thesis using on-chain and derivatives data.

    **The Thesis:**
    #{thesis}

    Using the Santiment MCP tools, fetch the following data for **#{slug}** over the last **#{time_period}**:

    **Whale Accumulation:**
    - `whale_transaction_count_100k_usd_to_inf` (interval: 1d) — whale transaction frequency
    - `whale_transaction_count_1m_usd_to_inf` (interval: 1d) — large whale transactions
    - `supply_on_exchanges` (interval: 1d) — declining = accumulation signal

    **Exchange Netflow:**
    - `exchange_inflow_usd` (interval: 1d)
    - `exchange_outflow_usd` (interval: 1d)
    - `exchange_balance` (interval: 1d)

    **Derivatives Sentiment:**
    - `total_funding_rates_aggregated_per_asset` (interval: 1d) — market positioning

    **On-Chain Valuation:**
    - `mvrv_usd` (interval: 1d) — over/undervaluation signal

    **Social Sentiment:**
    - `sentiment_weighted_total` (interval: 1d)
    - `social_volume_total` (interval: 1d)

    **Price Context:**
    - `price_usd` (interval: 1d)

    After gathering all data, produce a thesis validation report:

    1. **Thesis Summary** — restate the thesis in one sentence
    2. **Divergence Check** — is there a price vs. on-chain divergence? (price down + accumulation = bullish divergence; price up + distribution = bearish divergence)
    3. **Whale Behavior** — systematic buying (consistent, not spiking) vs speculative (erratic spikes)
    4. **Exchange Flow Analysis** — net inflow (selling pressure) vs net outflow (accumulation)
    5. **Funding Rate Signal** — negative = market is short-biased (contrarian long opportunity); positive = crowded long
    6. **MVRV Context** — under 1.0 = undervalued relative to cost basis; over 3.0 = overheated
    7. **Crowd Positioning** — low social volume + bearish sentiment = retail sidelined (contrarian signal)
    8. **Verdict** — CONFIRMED, PARTIALLY CONFIRMED, or KILLED, with specific data points supporting the conclusion

    Be direct and quantitative. The trader has a thesis — confirm or kill it with data. No hedging.
    Data sourced from Santiment.
    """

    response =
      Response.prompt()
      |> Response.user_message(message)

    {:reply, response, frame}
  end
end
