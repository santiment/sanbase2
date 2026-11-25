defmodule Sanbase.MarkdownTest do
  use ExUnit.Case, async: true

  alias Sanbase.Markdown

  test "renders basic markdown" do
    html = Markdown.to_html("**bold** and [link](https://santiment.net)")

    assert html =~ "<strong>bold</strong>"
    assert html =~ ~s(<a href="https://santiment.net">link</a>)
  end

  test "renders GFM tables, strikethrough and bare URLs" do
    html = Markdown.to_html("| a | b |\n|---|---|\n| 1 | 2 |\n\n~~old~~ https://santiment.net")

    assert html =~ "<table>"
    assert html =~ "<del>old</del>"
    assert html =~ ~s(<a href="https://santiment.net">)
  end

  test "escapes inline and block raw HTML instead of rendering it" do
    html = Markdown.to_html("hello <img src=x onerror=alert(1)>\n\n<script>alert(1)</script>")

    refute html =~ "<img"
    refute html =~ "<script"
    assert html =~ "&lt;img"
  end

  test "a markdown link cannot break out of its href attribute" do
    html = Markdown.to_html(~s{[click](http://example.com/?a=x" onerror="alert(1))})

    refute html =~ ~s(" onerror=")
  end

  test "drops javascript: link targets" do
    refute Markdown.to_html("[js](javascript:alert(1))") =~ "javascript:"
  end

  test "breaks: true turns single newlines into <br>" do
    assert Markdown.to_html("one\ntwo", breaks: true) =~ "<br"
    refute Markdown.to_html("one\ntwo") =~ "<br"
  end
end
