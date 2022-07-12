defmodule SanbaseWeb.Graphql.CustomTypes.SanitizedString do
  use Absinthe.Schema.Notation

  alias Absinthe.Blueprint.Input

  scalar :sanitized_string, name: "SanitizedString" do
    serialize(&serialize_sanitized_string/1)
    parse(&parse_sanitized_string/1)
  end

  scalar :sanitized_markdown_string, name: "SanitizedMarkdownString" do
    serialize(&serialize_sanitized_markdown_string/1)
    parse(&parse_sanitized_markdown_string/1)
  end

  defp serialize_sanitized_string(value) when is_binary(value) do
    HtmlSanitizeEx.strip_tags(value)
  end

  defp serialize_sanitized_string(nil), do: {:ok, nil}
  defp serialize_sanitized_string(_), do: :error

  defp parse_sanitized_string(string) when is_binary(string), do: {:ok, string}
  defp parse_sanitized_string(%Input.Null{}), do: {:ok, nil}
  defp parse_sanitized_string(_), do: :error

  defp serialize_sanitized_markdown_string(markdown) when is_binary(markdown) do
    # mark lines that start with "> " (valid markdown blockquote syntax)
    markdown = Regex.replace(~r/^>\s+([^\s+])/m, markdown, "REPLACED_BLOCKQUOTE\\1")
    markdown = HtmlSanitizeEx.Scrubber.scrub(markdown, Sanbase.CustomMarkdownScrubber)
    # Bring back the blockquotes
    Regex.replace(~r/^REPLACED_BLOCKQUOTE/m, markdown, "> ")
  end

  defp serialize_sanitized_markdown_string(nil), do: {:ok, nil}
  defp serialize_sanitized_markdown_string(_), do: :error

  defp parse_sanitized_markdown_string(string) when is_binary(string), do: {:ok, string}
  defp parse_sanitized_markdown_string(%Input.Null{}), do: {:ok, nil}
  defp parse_sanitized_markdown_string(_), do: :error
end
