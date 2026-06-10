defmodule Sanbase.Utils.HtmlSubsetScrubberTest do
  use ExUnit.Case, async: true

  defp scrub(input), do: HtmlSanitizeEx.Scrubber.scrub(input, Sanbase.Utils.HtmlSubsetScrubber)

  test "strips iframe tags entirely" do
    assert scrub(~S{<iframe src="javascript:alert(1)"></iframe>}) == ""
    assert scrub(~S{<iframe src="data:text/html,<script>alert(1)</script>"></iframe>}) == ""
    assert scrub(~S{<iframe src="https://evil.example"></iframe>}) == ""
  end

  test "strips script tags" do
    refute scrub(~S{<script>alert(1)</script>}) =~ "<script"
  end

  test "drops javascript: scheme on links and images" do
    refute scrub(~S{<a href="javascript:alert(1)">x</a>}) =~ "javascript:"
    refute scrub(~S{<img src="javascript:alert(1)">}) =~ "javascript:"
  end

  test "keeps allowed formatting tags" do
    assert scrub("<p>hello</p>") == "<p>hello</p>"
    assert scrub("<strong>bold</strong>") == "<strong>bold</strong>"
    assert scrub(~S{<a href="https://example.com">link</a>}) =~ ~S{href="https://example.com"}
  end
end
