defmodule Mix.Tasks.LoadTest.Cleanup do
  use Mix.Task

  import Ecto.Query

  @shortdoc "Remove load test users and clean up API key data"

  @moduledoc """
  Deletes all users with emails matching `%@sanload.test` and removes
  the generated API keys JSON file.

      mix load_test.cleanup
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {count, _} =
      Sanbase.Accounts.User
      |> where([u], like(u.email, "%@sanload.test"))
      |> Sanbase.Repo.delete_all()

    Mix.shell().info("Deleted #{count} load test users.")

    apikeys_path = Path.join([File.cwd!(), "load_test", "data", "apikeys.json"])

    if File.exists?(apikeys_path) do
      File.rm!(apikeys_path)
      Mix.shell().info("Removed #{apikeys_path}")
    end

    Mix.shell().info("Cleanup complete.")
  end
end
