defmodule Sanbase.DeepResearch.ReportMarkdown do
  @moduledoc """
  Post-processing for the final report markdown the agent delivers.

  Two jobs, both pure:

    * `reflow_sources/1` — tidy a run-together `Sources` section into one entry
      per line.
    * `split_charts/1` — lift fenced ` ```chart ` blocks out of the prose into
      normalized, renderer-agnostic chart specs (see
      `SanbaseWeb.DeepResearch.ChartRenderer`), leaving the surrounding markdown
      as ordinary segments.

  This is deliberately separate from `Sanbase.DeepResearch.Timeline`: the
  timeline folds the live event stream, this shapes the finished document.
  """

  @doc """
  Force a report's `Sources` section to render one entry per line. Idempotent —
  a no-op when already a list, when there are fewer than two sources, or when
  there is no Sources heading.
  """
  @spec reflow_sources(String.t()) :: String.t()
  def reflow_sources(md) when is_binary(md) do
    case Regex.run(~r/(^|\n)\#{0,6}\s*\**sources\**\s*:?\s*\n/i, md, return: :index) do
      [{start, len} | _] ->
        cut = start + len
        head = binary_part(md, 0, cut)
        tail = binary_part(md, cut, byte_size(md) - cut)
        {sources_block, rest} = split_at_next_heading(tail)
        reflow_tail(md, head, sources_block, rest)

      _ ->
        md
    end
  end

  def reflow_sources(md), do: md

  # The Sources block ends at the next Markdown heading (if any) — anything after
  # it is a separate section and must be left untouched, even if it has citation
  # markers of its own. `(^|\n)` (not just `\n`): a heading can sit directly
  # after the Sources heading (an empty Sources section), at position 0 of tail.
  defp split_at_next_heading(tail) do
    case Regex.run(~r/(^|\n)\#{1,6}\s/, tail, return: :index) do
      [{h_start, _} | _] ->
        {binary_part(tail, 0, h_start), binary_part(tail, h_start, byte_size(tail) - h_start)}

      _ ->
        {tail, ""}
    end
  end

  defp reflow_tail(md, head, sources_block, rest) do
    markers = length(Regex.scan(~r/\[\d+\]/, sources_block))

    lines_with_marker =
      sources_block |> String.split("\n") |> Enum.count(&Regex.match?(~r/\[\d+\]/, &1))

    entries =
      ~r/\s*(?=\[\d+\]\s)/
      |> Regex.split(sources_block)
      |> Enum.map(&(&1 |> String.replace(~r/^[-*]\s*/, "") |> String.trim()))
      |> Enum.reject(&(&1 == ""))

    # Leave untouched when there are fewer than two sources or it is already
    # one-per-line; otherwise re-bullet each entry.
    if markers < 2 or lines_with_marker >= markers or length(entries) < 2 do
      md
    else
      head <> Enum.map_join(entries, "\n", &"- #{&1}") <> "\n" <> rest
    end
  end

  @chart_fence ~r/```chart[ \t]*\n(.*?)\n?```/s

  @doc """
  Split report markdown into ordered render segments, lifting fenced
  ` ```chart ` blocks out as parsed chart specs:

    * `{:md, text}`    - a markdown run
    * `{:chart, spec}` - `%{type: "pie", title: String.t() | nil, slices: [%{label, value}]}`

  A fenced block whose body is not a valid chart spec is left as markdown, so a
  malformed block degrades to a visible code block rather than vanishing.
  """
  @spec split_charts(String.t()) :: [{:md, String.t()} | {:chart, map()}]
  def split_charts(md) when is_binary(md), do: md |> do_split_charts([]) |> Enum.reverse()
  def split_charts(_), do: []

  defp do_split_charts(md, acc) do
    case Regex.run(@chart_fence, md, return: :index) do
      [{ms, ml}, {gs, gl}] ->
        pre = binary_part(md, 0, ms)
        body = binary_part(md, gs, gl)
        full = binary_part(md, ms, ml)
        rest = binary_part(md, ms + ml, byte_size(md) - ms - ml)

        acc
        |> push_md(pre)
        |> push_chart(body, full)
        |> then(&do_split_charts(rest, &1))

      _ ->
        push_md(acc, md)
    end
  end

  defp push_md(acc, text) do
    if String.trim(text) == "", do: acc, else: [{:md, text} | acc]
  end

  defp push_chart(acc, body, full) do
    case parse_chart_spec(body) do
      {:ok, spec} -> [{:chart, spec} | acc]
      :error -> [{:md, full} | acc]
    end
  end

  defp parse_chart_spec(body) do
    case Jason.decode(String.trim(body)) do
      {:ok, obj} when is_map(obj) -> build_spec(to_string(obj["type"] || "pie"), obj)
      _ -> :error
    end
  end

  defp build_spec("pie", obj) do
    case chart_slices(obj) do
      [] -> :error
      slices -> {:ok, %{type: "pie", title: chart_title(obj), slices: slices}}
    end
  end

  defp build_spec(type, obj) when type in ["line", "area", "spike"] do
    case chart_series(obj) do
      [] ->
        :error

      series ->
        {:ok, %{type: "line", title: chart_title(obj), series: series, spike: chart_spike(obj)}}
    end
  end

  defp build_spec(_type, _obj), do: :error

  defp chart_title(obj) do
    case obj["title"] do
      t when is_binary(t) -> blank_to_nil(String.trim(t))
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp chart_slices(obj) do
    raw = obj["slices"] || obj["data"] || []

    if is_list(raw) do
      raw
      |> Enum.map(&one_slice/1)
      |> Enum.reject(&(is_nil(&1) or &1.label == "" or &1.value <= 0))
    else
      []
    end
  end

  defp one_slice(s) when is_map(s) do
    label = to_string(s["label"] || s["name"] || "")

    case s["value"] || s["count"] do
      v when is_number(v) -> %{label: label, value: v}
      _ -> nil
    end
  end

  defp one_slice(_), do: nil

  # `series: [%{label, points: [%{t, v}]}]`, or a flat `points: [...]` (single series).
  defp chart_series(obj) do
    raw =
      cond do
        is_list(obj["series"]) ->
          obj["series"]

        is_list(obj["points"]) ->
          [%{"label" => obj["label"] || obj["metric"], "points" => obj["points"]}]

        true ->
          []
      end

    raw
    |> Enum.map(&one_series/1)
    |> Enum.reject(&(is_nil(&1) or length(&1.points) < 2))
  end

  defp one_series(s) when is_map(s) do
    points =
      case s["points"] do
        list when is_list(list) -> list |> Enum.map(&one_point/1) |> Enum.reject(&is_nil/1)
        _ -> []
      end

    %{label: blank_to_nil(to_string(s["label"] || s["name"] || "")), points: points}
  end

  defp one_series(_), do: nil

  defp one_point(p) when is_map(p) do
    with t when is_number(t) <- num(p["t"] || p["time"] || p["x"]),
         v when is_number(v) <- num(p["v"] || p["value"] || p["y"]) do
      %{t: t, v: v}
    else
      _ -> nil
    end
  end

  defp one_point(_), do: nil

  defp chart_spike(obj) do
    case obj["spike"] do
      %{"from" => f, "to" => t} when is_number(f) and is_number(t) -> %{from: f, to: t}
      _ -> nil
    end
  end

  defp num(n) when is_number(n), do: n
  defp num(_), do: nil
end
