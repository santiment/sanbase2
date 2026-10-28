defmodule Sanbase.DiscordBot.UtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.DiscordBot.Utils

  test "splits ASCII content into chunks of at most max_length" do
    assert Utils.split_message("abcdefg", 3) == ["abc", "def", "g"]
  end

  test "counts characters, not bytes, so multibyte characters are never cut" do
    # Regression: a Bulgarian answer was split mid-character and the Discord send
    # crashed with Jason.EncodeError, so no answer was posted.
    content = String.duplicate("Здравей свят. ", 300)

    chunks = Utils.split_message(content, 1950)

    assert Enum.all?(chunks, &String.valid?/1)
    assert Enum.all?(chunks, &(String.length(&1) <= 1950))
    assert Enum.join(chunks) == content
  end
end
