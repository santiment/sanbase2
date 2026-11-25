defmodule SanbaseWeb.KnowledgeAnswerHTMLTest do
  use ExUnit.Case, async: true

  alias SanbaseWeb.KnowledgeAnswerHTML

  describe "to_html/1" do
    test "expands a {{date:...}} sentinel into a muted grey span" do
      html =
        KnowledgeAnswerHTML.to_html("- [BTC outlook](https://s/insight/1) {{date:2026-01-02}}")

      refute html =~ "{{date:"
      assert html =~ "(2026-01-02)"
      assert html =~ "color: #9ca3af"
    end

    test "expands the 'unknown date' sentinel too" do
      html = KnowledgeAnswerHTML.to_html("x {{date:unknown date}}")

      refute html =~ "{{date:"
      assert html =~ "(unknown date)"
    end

    test "leaves a sentinel-free answer as ordinary rendered markdown" do
      html = KnowledgeAnswerHTML.to_html("**bold** and a [link](https://x)")

      assert html =~ "<strong>bold</strong>"
      assert html =~ ~s(<a href="https://x">link</a>)
      refute html =~ "color: #9ca3af"
    end

    test "renders nil as an empty string rather than raising" do
      assert KnowledgeAnswerHTML.to_html(nil) == ""
    end

    test "raw HTML in the answer (script / event handlers) is escaped, never rendered" do
      html =
        KnowledgeAnswerHTML.to_html(
          "[1] insight: hello\n<script>alert(1)</script>\n<img src=x onerror=alert(2)>\n" <>
            "<div onclick=\"alert(3)\">x</div>\n[2] faq: q"
        )

      refute html =~ "<script"
      refute html =~ "<img"
      refute html =~ "<div"
      assert html =~ "&lt;script&gt;"
      assert html =~ "[1] insight: hello"
    end

    test "drops javascript: link targets" do
      html = KnowledgeAnswerHTML.to_html("- [x](javascript:alert(document.domain)) and more")

      refute html =~ "javascript:"
    end

    test "sanitizes malformed markdown instead of returning the raw source" do
      html = KnowledgeAnswerHTML.to_html("```\nunclosed fence\n<script>alert(1)</script>")

      refute html =~ "<script"
    end

    test "still expands the date sentinel after sanitizing" do
      html =
        KnowledgeAnswerHTML.to_html(
          "- [t](https://s/insight/1) {{date:2026-01-02}}\n<script>alert(1)</script>"
        )

      refute html =~ "<script"
      assert html =~ ~s(<span style="color: #9ca3af; white-space: nowrap">(2026-01-02\)</span>)
    end

    test "does not expand a malformed date token (only our own emitted shape)" do
      html = KnowledgeAnswerHTML.to_html("{{date:not-a-date}}")

      assert html =~ "{{date:not-a-date}}"
      refute html =~ "color: #9ca3af"
    end
  end
end
