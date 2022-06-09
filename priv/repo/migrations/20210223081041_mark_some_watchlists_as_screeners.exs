defmodule Sanbase.Repo.Migrations.MarkSomeWatchlistsAsScreeners do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.UserList
  alias Sanbase.Repo

  defmacro is_screener() do
    quote do
      fragment("""
      (function->>'name' = 'top_all_projects' or function->>'name' = 'selector')
      AND (slug IS NULL or slug != 'projects')
      """)
    end
  end

  def up do
    setup()

    from(UserList, where: is_screener())
    |> Repo.update_all(set: [is_screener: true])
  end

  def down, do: :ok

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
