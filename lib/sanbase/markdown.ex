defmodule Sanbase.Markdown do
  @moduledoc """
  Markdown to HTML conversion, backed by MDEx (comrak) with GitHub-flavored
  extensions: tables, strikethrough, task lists and bare-URL autolinks. Straight
  quotes, `--` and `...` become typographic punctuation, as Earmark did.

  Raw HTML in the source is escaped and shown as text, never rendered, and links
  with dangerous schemes (`javascript:` and similar) get an empty `href`. The
  output is not otherwise sanitized: callers that render untrusted markdown
  should still pass the result through `HtmlSanitizeEx`.
  """

  @type option :: {:breaks, boolean()}

  @doc """
  Converts markdown to HTML.

  Options:
    * `:breaks` - render single newlines inside a paragraph as `<br>`. Defaults to `false`.
  """
  @spec to_html(String.t(), [option]) :: String.t()
  def to_html(markdown, opts \\ []) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      extension: [strikethrough: true, table: true, tasklist: true, autolink: true],
      parse: [smart: true],
      render: [hardbreaks: Keyword.get(opts, :breaks, false), unsafe: false, escape: true]
    )
  end
end
