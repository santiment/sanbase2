defmodule Sanbase.Repo.Migrations.MigrateInsightsPublishedAt do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)

    run()
  end

  def down, do: :ok

  defp run do
    query = from(p in Post, where: p.ready_state == ^Post.published(), preload: [:featured_item])

    query
    |> Repo.all()
    |> Enum.map(fn
      %Post{featured_item: nil, updated_at: dt} = post ->
        Ecto.Changeset.change(post, published_at: dt)

      %Post{inserted_at: dt} = post ->
        Ecto.Changeset.change(post, published_at: dt)
    end)
    |> Enum.map(&Repo.update!/1)
  end
end
