defmodule Sanbase.HtmlTest do
  use ExUnit.Case, async: true

  alias Sanbase.HTML

  test "truncates text and preserves the tags around kept text" do
    html = "<div>1 2 3<div><span>4 5 6</span>7</div><ul><li>8</li><li>9</li></ul></div>"

    assert HTML.truncate_html(html, 0) == "<div></div>"
    assert HTML.truncate_html(html, 1) == "<div>1</div>"
    assert HTML.truncate_html(html, 2) == "<div>1 2</div>"
    assert HTML.truncate_html(html, 3) == "<div>1 2 3</div>"
    assert HTML.truncate_html(html, 4) == "<div>1 2 3<div><span>4</span></div></div>"
    assert HTML.truncate_html(html, 5) == "<div>1 2 3<div><span>4 5</span></div></div>"
    assert HTML.truncate_html(html, 6) == "<div>1 2 3<div><span>4 5 6</span></div></div>"
    assert HTML.truncate_html(html, 7) == "<div>1 2 3<div><span>4 5 6</span>7</div></div>"

    assert HTML.truncate_html(html, 8) ==
             "<div>1 2 3<div><span>4 5 6</span>7</div><ul><li>8</li></ul></div>"

    assert HTML.truncate_html(html, 9) ==
             "<div>1 2 3<div><span>4 5 6</span>7</div><ul><li>8</li><li>9</li></ul></div>"

    assert HTML.truncate_html(html, 10) ==
             "<div>1 2 3<div><span>4 5 6</span>7</div><ul><li>8</li><li>9</li></ul></div>"
  end

  test "with real insight with id 5679" do
    html = File.read!(Path.join(__DIR__, "data/insight_html_5679.txt"))

    original = replace_space_in_closing(html)

    for i <- Enum.take_every(0..140, 5) do
      result = html |> HTML.truncate_html(i) |> replace_trailing_closing_tags()
      assert String.contains?(original, result)
    end
  end

  test "with real insight with id 5680" do
    html = File.read!(Path.join(__DIR__, "data/insight_html_5680.txt"))

    original = replace_space_in_closing(html)

    for i <- Enum.take_every(0..140, 5) do
      result = html |> HTML.truncate_html(i) |> replace_trailing_closing_tags()
      assert String.contains?(original, result)
    end
  end

  test "#truncate_text" do
    text = "1 2"
    assert HTML.truncate_text(text, 100) == text

    text = "my name is tsetso  \n hello  \n  \n bye\nbye"
    assert HTML.truncate_text(text, 100) == text

    text = "my name is tsetso  \n hello  \t  \r bye\nbye"
    assert HTML.truncate_text(text, 100) == text
  end

  defp replace_trailing_closing_tags(html) do
    html
    |> String.replace("&amp;", "&")
    |> String.replace(~r{(</\w+>)+$}, "")
  end

  defp replace_space_in_closing(html) do
    String.replace(html, " />", "/>")
  end
end
