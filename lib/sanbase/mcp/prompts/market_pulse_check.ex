defmodule Sanbase.MCP.Prompts.MarketPulseCheck do
  @moduledoc """
  MCP prompt for retail traders to quickly assess whether a token's move
  is backed by real activity or just social noise.

  Fetches social volume, sentiment, whale transactions, and exchange flows
  and translates them into a simple, actionable read.
  """

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    %{
      slug: {:required, :string},
      time_period: {:string, {:default, "14d"}}
    }
  end

  @impl true
  def get_messages(%{slug: slug, time_period: time_period}, frame) do
    message = """
    You are a crypto market analyst helping a trader understand whether the current hype \
    around a token is backed by real activity or is just social noise.

    Using the Santiment MCP tools, fetch the following data for **#{slug}** over the last **#{time_period}**:

    **Social Signals:**
    - `social_volume_total` (interval: 1d) — are people talking about it?
    - `sentiment_weighted_total` (interval: 1d) — what's the mood?
    - `social_dominance_total` (interval: 1d) — how much attention vs other assets?

    **Whale Activity:**
    - `whale_transaction_count_100k_usd_to_inf` (interval: 1d) — are whales moving?
    - `whale_transaction_count_1m_usd_to_inf` (interval: 1d) — are large whales moving?

    **Exchange Flows:**
    - `exchange_inflow_usd` (interval: 1d) — selling pressure?
    - `supply_on_exchanges` (interval: 1d) — accumulation or distribution?

    **Price Context:**
    - `price_usd` (interval: 1d)

    After gathering all data, answer the trader's core question in plain language:

    **"Is this move real or is everyone just excited?"**

    Structure your response as:
    1. **The Quick Answer** — one sentence: real activity, pure hype, or mixed signals
    2. **Social Check** — what the social data says (volume spike timing, sentiment direction)
    3. **Smart Money Check** — what whales are doing (moved first? following retail?)
    4. **Exchange Flow Check** — accumulation or distribution pattern
    5. **What to Watch** — 1-2 specific things that would confirm or invalidate the move

    Keep it conversational and jargon-free. The trader doesn't want 12 metrics — \
    they want one clear signal with a reason behind it.
    Data sourced from Santiment.
    """

    response =
      Response.prompt()
      |> Response.user_message(%{"type" => "text", "text" => message})

    {:reply, response, frame}
  end
end
