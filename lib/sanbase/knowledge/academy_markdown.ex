defmodule Sanbase.Knowledge.AcademyMarkdown do
  @moduledoc """
  Turns Academy MDX/markdown into clean, heading-aware chunks for embedding.

  The Academy sources are Starlight MDX pages. Feeding them to the embedder
  verbatim puts YAML frontmatter, MDX `import` lines, JSX components,
  `<iframe>`/`<video>` embeds and image markdown into both the stored chunk
  and its vector. `TextChunker`'s markdown mode also splits at every heading
  without merging, so a heading followed by a sub-heading yields a chunk that
  is only the heading line (e.g. `## SAN_MVRV_RATIO`), and those stubs win
  vector search on keyword-like queries.

  This module:

    * `clean/1` strips the page-level noise while keeping readable text.
      Fenced code blocks and inline code spans are left untouched, and JSX
      wrapper components such as `<Notebox>` keep their inner text.
    * `chunk/2` splits the cleaned page into sections by ATX heading (ignoring
      `#` lines inside code fences), merges sections that are too small to
      stand alone into the following ones, and splits oversized sections with
      `TextChunker` so they keep the configured overlap. Every chunk carries
      the nearest heading and the heading breadcrumb it sits under.
    * `embedding_text/2` prepends `Title > Breadcrumb` to the chunk content, so
      the vector knows which page and section a short chunk belongs to. Only
      the embedded text gets the header; the stored content stays as-is.
  """

  @default_chunk_size 2000
  @default_chunk_overlap 200
  # Sections shorter than this are merged forward into the next section. 800 was
  # picked by `Sanbase.Knowledge.AcademySearchEval` on 2026-09-29: 300 gave smaller
  # chunks that lost ranking and answer-fact recall; 800 matched the old index on
  # ranking with ~25% fewer chunks.
  @default_min_chunk_chars 800
  # Links whose URL is longer than this are reduced to their text. These are
  # URL-encoded chart/GraphiQL links that add hundreds of characters of noise.
  @max_link_url_length 200

  @fence_regex ~r/^\s{0,3}(`{3,}|~{3,})/
  # A closing fence has no info string, so a "```python" line inside a block does not close it.
  @closing_fence_regex ~r/^\s{0,3}(`{3,}|~{3,})\s*$/
  @heading_regex ~r/^\s{0,3}(\#{1,6})\s+(.+?)\s*#*\s*$/
  @inline_code_regex ~r/`[^`\n]*`/

  @type chunk :: %{
          content: String.t(),
          heading: String.t() | nil,
          breadcrumb: [String.t()]
        }

  @doc """
  Remove frontmatter, MDX/HTML markup and media embeds from `markdown`.
  Code (fenced blocks and inline spans) is preserved verbatim.
  """
  @spec clean(String.t()) :: String.t()
  def clean(markdown) when is_binary(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> strip_frontmatter()
    |> segments()
    |> Enum.map_join("\n", fn
      {:code, text} -> text
      {:prose, text} -> clean_prose(text)
    end)
    |> String.replace(~r/[ \t]+$/m, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  @doc """
  Clean and split `markdown` into chunks.

  Options:
    * `:chunk_size` - max chunk length in characters (default #{@default_chunk_size})
    * `:chunk_overlap` - overlap used when an oversized section is split
      (default #{@default_chunk_overlap})
    * `:min_chunk_chars` - sections shorter than this are merged into the next
      section (default #{@default_min_chunk_chars})
  """
  @spec chunk(String.t(), keyword()) :: [chunk()]
  def chunk(markdown, opts \\ []) when is_binary(markdown) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    chunk_overlap = Keyword.get(opts, :chunk_overlap, @default_chunk_overlap)
    min_chars = Keyword.get(opts, :min_chunk_chars, @default_min_chunk_chars)

    markdown
    |> clean()
    |> sections()
    |> merge_small_sections(min_chars, chunk_size)
    |> Enum.flat_map(&split_oversized(&1, chunk_size, chunk_overlap))
  end

  @doc """
  Text sent to the embedder for a chunk: a `Title > Breadcrumb` header line
  followed by the chunk content.
  """
  @spec embedding_text(String.t() | nil, chunk()) :: String.t()
  def embedding_text(title, %{content: content} = chunk) do
    breadcrumb = Map.get(chunk, :breadcrumb, [])

    header =
      [title | breadcrumb]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.dedup()
      |> Enum.join(" > ")

    if header == "", do: content, else: header <> "\n\n" <> content
  end

  @doc """
  Plain-text form of a heading: link syntax, emphasis, inline code markers,
  HTML tags and `{#anchor}` suffixes removed.
  """
  @spec clean_heading(String.t()) :: String.t()
  def clean_heading(heading) when is_binary(heading) do
    heading
    |> String.replace(~r/\{#[^}]*\}\s*$/, "")
    |> String.replace(~r/!?\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/<\/?[A-Za-z][^<>]*>/, "")
    |> String.replace(~r/(\*\*|__)(.+?)\1/, "\\2")
    |> String.replace(~r/(?<![\w*])[*_]([^*_]+)[*_](?![\w*])/, "\\1")
    |> String.replace("`", "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  True when `text` still contains markup that `clean/1` is meant to remove:
  frontmatter, MDX imports, media embeds, JSX components or image markdown.
  Used by the eval and index stats to measure noise in stored chunks.
  """
  @spec markup_residue?(String.t()) :: boolean()
  def markup_residue?(text) when is_binary(text) do
    Regex.match?(
      ~r/(\A---\n[A-Za-z_]+:)|(^import\s.+\sfrom\s)|(<(iframe|video|img|audio|embed)\b)|(<[A-Z][A-Za-z]+[\s>\/])|(!\[[^\]]*\]\()/m,
      text
    )
  end

  # Cleaning ------------------------------------------------------------

  defp strip_frontmatter(text) do
    String.replace(text, ~r/\A\s*---\n.*?\n---[ \t]*(\n|\z)/s, "", global: false)
  end

  # Split text into alternating prose and fenced-code segments so cleaning
  # never touches code. An unterminated fence runs to the end of the text.
  defp segments(text) do
    {segments, current, fence} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], [], nil}, &segment_step/2)

    kind = if fence, do: :code, else: :prose

    segments
    |> push_segment(kind, current)
    |> Enum.reverse()
  end

  # State: {finished segments, lines of the current segment (reversed), open fence}.
  defp segment_step(line, {segments, current, nil}) do
    case fence_marker(line) do
      nil -> {segments, [line | current], nil}
      marker -> {push_segment(segments, :prose, current), [line], marker}
    end
  end

  defp segment_step(line, {segments, current, open}) do
    if closes_fence?(open, line),
      do: {push_segment(segments, :code, [line | current]), [], nil},
      else: {segments, [line | current], open}
  end

  defp fence_marker(line) do
    case Regex.run(@fence_regex, line, capture: :all_but_first) do
      [marker] -> marker
      nil -> nil
    end
  end

  # A fence closes on a bare marker of the same character with at least the opening length.
  defp closes_fence?(open, line) do
    case Regex.run(@closing_fence_regex, line, capture: :all_but_first) do
      [marker] ->
        String.first(open) == String.first(marker) and
          String.length(marker) >= String.length(open)

      nil ->
        false
    end
  end

  defp push_segment(segments, _kind, []), do: segments

  defp push_segment(segments, kind, lines) do
    [{kind, lines |> Enum.reverse() |> Enum.join("\n")} | segments]
  end

  defp clean_prose(text) do
    text
    |> String.replace(~r/^\s*import\s+.*\s+from\s+['"].*$/m, "")
    |> String.replace(~r/^\s*import\s+['"].*$/m, "")
    |> String.replace(~r/^\s*export\s+(const|let|default|function)\b.*$/m, "")
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.replace(~r/\{\/\*.*?\*\/\}/s, "")
    |> String.replace(~r/<(iframe|video|audio|script|style)\b[^>]*>.*?<\/\1\s*>/si, "")
    |> String.replace(~r/<(iframe|video|audio|img|source|embed)\b[^>]*>/si, "")
    |> String.replace(~r/!\[[^\]]*\]\([^)]*\)/, "")
    |> String.replace(~r/\[\s*\]\([^)]*\)/, "")
    |> String.replace(~r/\[([^\]]*)\]\(([^)\s]{#{@max_link_url_length},})\)/, "\\1")
    |> strip_tags_outside_inline_code()
    |> compact_tables()
  end

  # Remove remaining HTML/JSX tags but keep their inner text (`<Notebox>`,
  # `<code>`, `<br>`). Inline code spans such as `<metric>` are kept as-is.
  defp strip_tags_outside_inline_code(text) do
    @inline_code_regex
    |> Regex.split(text, include_captures: true)
    |> Enum.map_join(fn part ->
      if String.starts_with?(part, "`") and String.ends_with?(part, "`") do
        part
      else
        String.replace(part, ~r/<\/?[A-Za-z][A-Za-z0-9.]*(\s[^<>]*)?\/?>/s, "")
      end
    end)
  end

  # Table rows are padded with runs of spaces and dashes for alignment in the
  # source; collapse them so they do not eat the chunk budget.
  defp compact_tables(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if String.starts_with?(String.trim_leading(line), "|") do
        line
        |> String.replace(~r/[ \t]{2,}/, " ")
        |> String.replace(~r/-{4,}/, "---")
      else
        line
      end
    end)
  end

  # Sections -------------------------------------------------------------

  # Split cleaned text into sections at ATX headings outside code fences.
  # Each section carries its heading and the breadcrumb of enclosing headings.
  defp sections(text) do
    {sections, current, _stack, _fence} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], new_section(nil, []), [], nil}, &section_step/2)

    [current | sections]
    |> Enum.reverse()
    |> Enum.map(fn section ->
      text = section.lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()
      section |> Map.delete(:lines) |> Map.put(:text, text)
    end)
    |> Enum.reject(&(&1.text == ""))
  end

  # State: {finished sections, current section, heading stack, open fence}.
  defp section_step(line, {sections, current, stack, fence}) when fence != nil do
    fence = if closes_fence?(fence, line), do: nil, else: fence
    {sections, add_line(current, line), stack, fence}
  end

  defp section_step(line, {sections, current, stack, nil}) do
    case {fence_marker(line), parse_heading(line)} do
      {nil, {level, title}} ->
        stack = Enum.reject(stack, fn {lvl, _} -> lvl >= level end) ++ [{level, title}]
        section = title |> new_section(Enum.map(stack, &elem(&1, 1))) |> add_line(line)
        {[current | sections], section, stack, nil}

      {marker, _} ->
        {sections, add_line(current, line), stack, marker}
    end
  end

  defp new_section(heading, breadcrumb),
    do: %{heading: heading, breadcrumb: breadcrumb, lines: [], text: nil}

  defp add_line(section, line), do: %{section | lines: [line | section.lines]}

  defp parse_heading(line) do
    case Regex.run(@heading_regex, line, capture: :all_but_first) do
      [hashes, text] ->
        case clean_heading(text) do
          "" -> nil
          heading -> {String.length(hashes), heading}
        end

      nil ->
        nil
    end
  end

  # Merge a section shorter than `min_chars` with the sections after it (while
  # the result fits `chunk_size`). The merged chunk keeps the first section's
  # heading: a `## SAN_X` stub followed by its `##### SAN_X(args)` body becomes
  # one chunk labelled `SAN_X`. A short tail is merged back into the previous
  # chunk when it fits.
  defp merge_small_sections(sections, min_chars, chunk_size) do
    sections
    |> Enum.reduce([], fn
      section, [prev | rest] = acc ->
        if mergeable?(prev, section, prev, min_chars, chunk_size),
          do: [join_sections(prev, section) | rest],
          else: [section | acc]

      section, [] ->
        [section]
    end)
    |> merge_short_tail(min_chars, chunk_size)
    |> Enum.reverse()
  end

  # `small` is the section whose size decides; the merged text must fit `chunk_size`.
  # A heading-only section is never appended to a chunk that has body text: it would
  # end that chunk with a heading whose content lands in the next chunk (Sansheets
  # pages: `## SAN_B` at the end of the `SAN_A` chunk). It starts a chunk instead,
  # and its content merges into it.
  defp mergeable?(first, second, small, min_chars, chunk_size) do
    String.length(small.text) < min_chars and
      String.length(first.text) + 2 + String.length(second.text) <= chunk_size and
      not (heading_only?(second) and not heading_only?(first))
  end

  defp heading_only?(%{text: text}) do
    text
    |> String.split("\n", trim: true)
    |> Enum.all?(&(String.trim(&1) == "" or parse_heading(&1) != nil))
  end

  defp join_sections(first, second), do: %{first | text: first.text <> "\n\n" <> second.text}

  defp merge_short_tail([last, prev | rest], min_chars, chunk_size) do
    if mergeable?(prev, last, last, min_chars, chunk_size),
      do: [join_sections(prev, last) | rest],
      else: [last, prev | rest]
  end

  defp merge_short_tail(sections, _min_chars, _chunk_size), do: sections

  defp split_oversized(%{text: text} = section, chunk_size, chunk_overlap) do
    pieces =
      if String.length(text) <= chunk_size do
        [text]
      else
        text
        |> TextChunker.split(
          chunk_size: chunk_size,
          chunk_overlap: chunk_overlap,
          format: :markdown
        )
        |> Enum.map(&String.trim(&1.text))
        |> Enum.reject(&(&1 == ""))
      end

    Enum.map(pieces, fn piece ->
      %{content: piece, heading: section.heading, breadcrumb: section.breadcrumb}
    end)
  end
end
