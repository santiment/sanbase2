defmodule Sanbase.Knowledge.Citations do
  @moduledoc """
  Turns the model's structured answer into the final, citation-correct markdown.

  The answer model runs on a small model that cannot reliably reproduce long
  `[Academy: label](https://…)` markers verbatim — it flattens them to plain
  text and drops URLs. So instead of trusting it to format links, we make it
  do the easy part and we do the formatting:

    * The prompt numbers every provided context block (`Source [3] — …`).
    * The model returns JSON — `{answer, source_ids, financial_disclaimer}` —
      and cites inline using only the bare token `[3]` (trivial to copy right).
    * Here we expand each known `[n]` into a real `[Prefix: label](url)`
      markdown link, build a grouped `Sources` section from the registry we
      control, and append the financial disclaimer when the model flagged it.

  Every link comes from the `registry` (a list of `Sanbase.Knowledge.Context`
  markers, each tagged with its `:id`), never from model output, so links are
  always present and correct. `response_format/0` is the OpenAI structured
  output schema that guarantees the JSON shape.
  """

  alias Sanbase.Knowledge.Context

  @disclaimer "*Disclaimer: This is general information for educational purposes only, not financial or investment advice. Santiment is not a licensed financial adviser. Do your own research and consult a licensed professional before making any investment decision.*"

  # Sources are grouped under these headers, in this order, in the final answer.
  @group_order [insight: "Insight", academy: "Academy", faq: "FAQ"]

  @doc """
  The OpenAI `response_format` (strict JSON schema) for the answer call.

  `strict: true` requires every property to be listed in `required` and forbids
  extra keys, so the model can only return this exact shape.
  """
  @spec response_format() :: map()
  def response_format() do
    %{
      "type" => "json_schema",
      "json_schema" => %{
        "name" => "knowledge_answer",
        "strict" => true,
        "schema" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["answer", "source_ids", "financial_disclaimer"],
          "properties" => %{
            "answer" => %{
              "type" => "string",
              "description" =>
                "The answer in markdown. Cite a provided context block inline using only its bare numeric token, e.g. [3], placed right after the claim it supports. Do NOT write URLs, link markdown, or a Sources section."
            },
            "source_ids" => %{
              "type" => "array",
              "items" => %{"type" => "integer"},
              "description" => "The ids of the context blocks actually used in the answer."
            },
            "financial_disclaimer" => %{
              "type" => "boolean",
              "description" =>
                "true if the answer touches trading, investing, buying, selling, or market timing; false for purely technical, account, or product answers."
            }
          }
        }
      }
    }
  end

  @doc """
  Render the model's raw JSON `content` into the final markdown answer.

  `registry` is the list of `Context.marker/2` maps, each carrying an integer
  `:id`, that were placed in the prompt. On a parse failure (the model didn't
  honour the schema) the raw content is returned unchanged as a best-effort
  fallback, so a malformed response still surfaces an answer. The model name is
  tracked separately in the question/answer log, not shown in the answer.
  """
  @spec render(String.t(), [map()]) :: String.t()
  def render(content, registry) do
    case decode(content) do
      {:ok, %{answer: answer, source_ids: source_ids, disclaimer?: disclaimer?}} ->
        by_id = Map.new(registry, &{&1.id, &1})

        cited = cited_ids(answer, source_ids, registry)

        [
          expand_inline(answer, by_id),
          build_sources(cited, registry),
          if(disclaimer?, do: @disclaimer)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")

      :error ->
        content
    end
  end

  # Parse the structured response, tolerating missing optional keys. Requires at
  # least a string `answer`; anything else means the model ignored the schema.
  defp decode(content) do
    with {:ok, %{"answer" => answer} = map} when is_binary(answer) <- Jason.decode(content) do
      {:ok,
       %{
         answer: answer,
         source_ids:
           map |> Map.get("source_ids", []) |> List.wrap() |> Enum.filter(&is_integer/1),
         disclaimer?: Map.get(map, "financial_disclaimer", false) == true
       }}
    else
      _ -> :error
    end
  end

  # Replace each known `[n]` token with its full markdown link. Unknown numeric
  # tokens (no matching id) are left untouched — they may be real text, e.g. an
  # array index in a code sample.
  defp expand_inline(answer, by_id) do
    Regex.replace(~r/\[(\d+)\]/, answer, fn whole, num ->
      case Map.fetch(by_id, String.to_integer(num)) do
        {:ok, marker} -> link(marker)
        :error -> whole
      end
    end)
  end

  # A source belongs in the Sources section if it was cited inline OR listed in
  # the model's `source_ids`. Keeping inline-cited ids guarantees every inline
  # link also appears in Sources even if the model forgot to list it.
  defp cited_ids(answer, source_ids, registry) do
    known = MapSet.new(registry, & &1.id)

    inline =
      ~r/\[(\d+)\]/
      |> Regex.scan(answer)
      |> Enum.map(fn [_, num] -> String.to_integer(num) end)

    (inline ++ source_ids)
    |> Enum.filter(&MapSet.member?(known, &1))
    |> MapSet.new()
  end

  defp build_sources(cited_ids, registry) do
    cited = Enum.filter(registry, &MapSet.member?(cited_ids, &1.id))

    groups =
      @group_order
      |> Enum.map(fn {source, header} ->
        entries =
          cited
          |> Enum.filter(&(&1.source == source))
          |> Enum.sort_by(& &1.id)

        {header, entries}
      end)
      |> Enum.reject(fn {_header, entries} -> entries == [] end)
      |> Enum.map(fn {header, entries} ->
        bullets = Enum.map_join(entries, "\n", fn m -> "- #{labelled_link(m)}" end)
        "**#{header}:**\n#{bullets}"
      end)

    case groups do
      [] -> ""
      _ -> "### Sources\n\n" <> Enum.join(groups, "\n\n")
    end
  end

  # Inline citation: keep the source prefix so the link reads as a full marker,
  # matching the rest of the body, e.g. `[Academy: Getting Started](url)`.
  defp link(%{prefix: prefix, label: label, url: url}) do
    "[#{prefix}: #{Context.escape_label(label)}](#{safe_url(url)})"
  end

  # Sources-section entry: the source prefix is already the group header, so the
  # bullet shows only the label, e.g. `[Getting Started](url)`.
  defp labelled_link(%{label: label, url: url}) do
    "[#{Context.escape_label(label)}](#{safe_url(url)})"
  end

  # The label is escaped, but the URL is interpolated into the `(...)` of a
  # markdown link too. A URL carrying a `)` (or a non-web scheme like
  # `javascript:`) would otherwise break out of the link or forge its target.
  # Allow only http(s); collapse anything else to "#", and percent-encode the
  # characters that are significant inside a markdown link target so the URL
  # stays inert.
  defp safe_url(url) do
    url = to_string(url)

    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        url
        |> String.replace("\\", "%5C")
        |> String.replace("(", "%28")
        |> String.replace(")", "%29")
        |> String.replace(" ", "%20")

      _ ->
        "#"
    end
  end
end
