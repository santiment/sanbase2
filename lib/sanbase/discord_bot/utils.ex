defmodule Sanbase.DiscordBot.Utils do
  @moduledoc """
  Discord bot utils
  """

  @spec split_message(String.t(), pos_integer()) :: list(String.t())
  def split_message(content, max_length) do
    Regex.scan(~r/.{1,#{max_length}}/s, content)
    |> Enum.map(&Enum.at(&1, 0))
  end
end
