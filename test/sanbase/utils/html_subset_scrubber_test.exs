defmodule Sanbase.Utils.HtmlSubsetScrubberTest do
  use ExUnit.Case, async: true

  defp scrub(input), do: HtmlSanitizeEx.Scrubber.scrub(input, Sanbase.Utils.HtmlSubsetScrubber)

  test "keeps http(s) iframe embeds but strips dangerous-scheme src" do
    # Legitimate embeds are preserved
    assert scrub(~S{<iframe src="https://www.youtube.com/embed/abc"></iframe>}) =~
             ~S{src="https://www.youtube.com/embed/abc"}

    # javascript: / data: schemes are dropped (no script execution)
    refute scrub(~S{<iframe src="javascript:alert(1)"></iframe>}) =~ "javascript:"
    refute scrub(~S{<iframe src="data:text/html,<script>alert(1)</script>"></iframe>}) =~ "data:"
  end

  test "strips dangerous iframe attributes (srcdoc, event handlers)" do
    # srcdoc would allow inline HTML/JS - must be stripped
    refute scrub(~S{<iframe srcdoc="<script>alert(1)</script>"></iframe>}) =~ "srcdoc"
    refute scrub(~S{<iframe src="https://ok.example" onload="alert(1)"></iframe>}) =~ "onload"
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
