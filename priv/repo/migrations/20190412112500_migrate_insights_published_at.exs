defmodule Sanbase.Repo.Migrations.MigrateInsightsPublishedAt do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Insight.Post

  def up() do
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
    run()
  end

  def down(), do: :ok

  defp run() do
    query = from(p in Post, where: p.ready_state == ^Post.published(), preload: [:featured_item])

    query
    |> Repo.all()
    |> Enum.map(fn
      %Post{featured_item: nil, updated_at: dt} = post ->
        post |> Ecto.Changeset.change(published_at: dt)

      %Post{inserted_at: dt} = post ->
        post |> Ecto.Changeset.change(published_at: dt)
    end)
    |> Enum.map(&Repo.insert!/1)
  end
end
