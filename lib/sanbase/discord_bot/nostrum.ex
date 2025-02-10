defmodule Sanbase.Nostrum do
  @moduledoc false
  def init do
    Application.put_env(:nostrum, :token, System.get_env("DISCORD_BOT_QUERY_TOKEN"))
  end

  def enabled? do
    Application.get_env(:nostrum, :token) != nil
  end
end
