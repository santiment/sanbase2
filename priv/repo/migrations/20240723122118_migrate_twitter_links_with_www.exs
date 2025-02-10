defmodule Sanbase.Repo.Migrations.MigrateTwitterLinksWithWww do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Project

  def up do
    setup()
    migrate_twitter_handles()
  end

  def down do
    :ok
  end

  def migrate_twitter_handles do
    from(
      p in Project,
      where: not is_nil(p.slug) and not is_nil(p.ticker) and not is_nil(p.twitter_link)
    )
    |> select([p], {p.id, p.twitter_link})
    |> Sanbase.Repo.all()
    |> Enum.reject(fn {_id, link} ->
      String.starts_with?(link, "https://twitter.com/") or
        String.starts_with?(link, "https://x.com/")
    end)
    |> Enum.map(fn {id, link} ->
      new_link =
        link
        |> String.replace("https://www.twitter.com/", "https://twitter.com/")
        |> case do
          "https://twitter.com/" <> _ = link -> link
          _ -> nil
        end

      {id, new_link}
    end)
    |> Enum.each(fn {id, new_link} ->
      Project
      |> Sanbase.Repo.get!(id)
      |> Project.changeset(%{twitter_link: new_link})
      |> Sanbase.Repo.update!()
    end)
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
