defmodule SanbaseWeb.Graphql.CustomTypes.SanitizedString do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias Absinthe.Blueprint.Input

  scalar :sanitized_string_no_tags, name: "SanitizedStringNoTags" do
    serialize(&serialize_sanitized_string_no_tags/1)
    parse(&parse_sanitized_string_no_tags/1)
  end

  scalar :sanitized_html_subset_string, name: "SanitizedHtmlSubsetString" do
    serialize(&serialize_sanitized_html_subset_string/1)
    parse(&parse_sanitized_html_subset_string/1)
  end

  defp serialize_sanitized_string_no_tags(value) when is_binary(value) do
    HtmlSanitizeEx.strip_tags(value)
  end

  defp serialize_sanitized_string_no_tags(nil), do: {:ok, nil}
  defp serialize_sanitized_string_no_tags(_), do: :error

  defp parse_sanitized_string_no_tags(string) when is_binary(string), do: {:ok, string}
  defp parse_sanitized_string_no_tags(%Input.Null{}), do: {:ok, nil}
  defp parse_sanitized_string_no_tags(_), do: :error

  defp serialize_sanitized_html_subset_string(string) when is_binary(string) do
    string = Regex.replace(~r/^>\s+([^\s+])/m, string, "REPLACED_BLOCKQUOTE\\1")
    string = HtmlSanitizeEx.Scrubber.scrub(string, Sanbase.Utils.HtmlSubsetScrubber)
    # Bring back the blockquotes
    Regex.replace(~r/^REPLACED_BLOCKQUOTE/m, string, "> ")
  end

  defp serialize_sanitized_html_subset_string(nil), do: {:ok, nil}
  defp serialize_sanitized_html_subset_string(_), do: :error

  defp parse_sanitized_html_subset_string(string) when is_binary(string), do: {:ok, string}
  defp parse_sanitized_html_subset_string(%Input.Null{}), do: {:ok, nil}
  defp parse_sanitized_html_subset_string(_), do: :error
end
