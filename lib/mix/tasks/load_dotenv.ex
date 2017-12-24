defmodule Mix.Tasks.LoadDotenv do
  use Mix.Task

  @shortdoc "Load the dotenv config"

  @moduledoc """
  Loads the dotenv config
  """

  def run(_args) do
    Envy.auto_load()
  end
end
