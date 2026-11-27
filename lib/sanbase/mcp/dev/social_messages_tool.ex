defmodule Sanbase.MCP.Dev.SocialMessagesTool do
  @moduledoc """
  What the crowd is saying about a coin: a stratified sample of raw social posts plus a
  stats block computed over ALL matching posts (total vs sampled, volume curve, sentiment
  balance, trend words, top channels). Internal Santiment social data from metrics-hub;
  cite it as "Santiment social messages".

  Each message has a `stratum`:
  - `head`: the top posts by engagement
  - `random`: an unbiased sample
  - `poles`: oversampled bullish and bearish extremes

  Judge how common a view is and the overall mood only from the `random` stratum and the
  stats block. Use `head` and `poles` to see what spread and where the disagreement is.

  If the stats say zero messages, there is no crowd data for the asset in that window:
  report that plainly instead of filling the gap from other sources.

  Results are large (roughly 1.5 tokens per word of `max_words`). Do not read them in
  your main context. Write the result to a file when you can, then work from the file:
  compute numbers with code (e.g. pandas over `messages`), and hand the message texts
  to a cheaper model or subagent to pull out topics, narratives and claims. Cite counts
  and shares from the `stats` block. If you can only read the result directly, keep
  `max_words` small.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.Dev.Server
  alias Sanbase.MCP.ToolError
  alias Sanbase.SocialData.SampleDocuments

  @default_max_words 10_000
  @max_words_limit 400_000

  def name(), do: "social_messages"

  @impl true
  def annotations() do
    %{
      "title" => "Social Messages",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:asset, :string,
      required: true,
      description: "A project slug (e.g. 'bitcoin') or a free search word."
    )

    field(:from, :string,
      description: "Window start: ISO-8601 or date math like 'now-24h'. Defaults to 24 hours ago."
    )

    field(:to, :string,
      description: "Window end: ISO-8601 or date math like 'now'. Defaults to now."
    )

    field(:sources, {:list, :string},
      description:
        "Source ids, any of: #{Enum.join(SampleDocuments.sources(), ", ")}. " <>
          "`twitter` means all the twitter indices: pass [\"twitter\"] for Twitter only. " <>
          "Defaults to #{Enum.join(SampleDocuments.default_sources(), ", ")}."
    )

    field(:max_words, :integer,
      description:
        "Max total words across the sampled message texts (default #{@default_max_words}, " <>
          "at most #{@max_words_limit}). More words means more posts and a bigger response."
    )
  end

  @impl true
  def execute(%{asset: asset} = params, frame) do
    Server.log_tool_call(frame.assigns.current_user, "social_messages", asset)

    opts = [
      from: params[:from],
      to: params[:to],
      sources: params[:sources],
      max_words: params |> Map.get(:max_words) |> clamp_max_words()
    ]

    case SampleDocuments.sample(asset, opts) do
      {:ok, result} ->
        {:reply, Response.json(Response.tool(), result), frame}

      {:error, {kind, message}} ->
        {:reply, Response.error(Response.tool(), ToolError.tag(kind, message)), frame}
    end
  end

  defp clamp_max_words(n) when is_integer(n) and n > 0, do: min(n, @max_words_limit)
  defp clamp_max_words(_), do: @default_max_words
end
