defmodule Sanbase.MCP.UseCasesCatalogTool do
  @moduledoc """
  **CALL THIS TOOL FIRST** when answering crypto analysis questions to check if the query
  matches any predefined analytical strategies.

  This tool returns a catalog of proven analytical use cases with complete step-by-step
  execution instructions. Each use case is a ready-to-use analytical recipe that:
  - Identifies the analytical goal (e.g., "Is this asset near a top?")
  - Provides 5-10 detailed steps referencing specific MCP tools to call
  - Explains how to interpret the combined results
  - Ensures comprehensive multi-signal analysis following best practices

  ## When to Use This Tool

  **ALWAYS call this tool FIRST** when the user asks questions like:
  - "Is [asset] near a top?" or "Is [asset] overbought?"
  - "Should I buy/sell [asset]?"
  - "Is [asset] in an accumulation zone?"
  - "What's the market sentiment for [asset]?"
  - Any question about market timing, price predictions, or trading decisions

  ## How to Use This Tool

  1. **Call this tool first** (no parameters needed)
  2. **Compare** the user's query to the available use case titles and descriptions
  3. **If a use case matches**: Follow the step-by-step instructions provided
     - Each step tells you exactly which tool to call and with what parameters
     - Execute the steps in order, gathering data from each
     - Synthesize results using the interpretation guide
  4. **If no use case matches**: Proceed with ad-hoc analysis using individual tools

  ## Benefits of Using This Tool First

  - **Comprehensive analysis**: Use cases combine multiple signals (not just one metric)
  - **Best practices**: Strategies are based on proven analytical frameworks
  - **Time-saving**: Get a complete analytical recipe instead of guessing which metrics to use
  - **Better answers**: Multi-signal approaches provide more reliable insights

  ## Example Use Cases Available

  - **Identify Market Tops**: Combines social volume, sentiment, network activity, MVRV,
    and mean dollar age to detect potential tops with high confidence
  - More use cases will be added over time

  ## Response Format

  Returns a list of use cases, each containing:
  - `title`: What analytical question this use case answers
  - `steps`: Plain text instructions with specific tool calls and parameters
  - `interpretation`: How to combine and interpret the results
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.UseCasesCatalog

  schema do
  end

  @impl true
  def execute(_params, frame) do
    use_cases = UseCasesCatalog.all_use_cases()

    simplified_use_cases =
      Enum.map(use_cases, fn use_case ->
        %{
          title: use_case.title,
          steps: use_case.steps,
          interpretation: use_case.interpretation
        }
      end)

    {:reply, Response.json(Response.tool(), simplified_use_cases), frame}
  end
end
