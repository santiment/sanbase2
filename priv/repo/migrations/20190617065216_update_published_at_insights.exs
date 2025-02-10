defmodule Sanbase.Repo.Migrations.UpdatePublishedAtInsights do
  @moduledoc false
  use Ecto.Migration
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
    query =
      from(p in Post,
        where: p.ready_state == ^Post.published() and is_nil(p.published_at),
        preload: [:featured_item]
      )

    query
    |> Repo.all()
    |> Enum.map(fn
      %Post{featured_item: nil, updated_at: dt} = post ->
        Ecto.Changeset.change(post, published_at: DateTime.to_naive(dt))

      %Post{inserted_at: dt} = post ->
        Ecto.Changeset.change(post, published_at: DateTime.to_naive(dt))
    end)
    |> Enum.map(&Repo.update!/1)
  end
end
