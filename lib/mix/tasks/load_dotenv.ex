defmodule Mix.Tasks.LoadDotenv do
  @shortdoc "Load the dotenv config"

  @moduledoc """
  Loads the dotenv config
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Envy.auto_load()
  end
end
