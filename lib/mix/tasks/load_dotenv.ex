defmodule Mix.Tasks.LoadDotenv do
  use Mix.Task

  @shortdoc "Load the dotenv config"

  @moduledoc """
  Loads the dotenv config
  """

  @impl Mix.Task
  def run(_args) do
    Sanbase.EnvConfigLoader.auto_load()
  end
end
