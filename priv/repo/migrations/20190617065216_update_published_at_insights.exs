defmodule Sanbase.Repo.Migrations.UpdatePublishedAtInsights do
  use Ecto.Migration

  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Insight.Post

  def up() do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()

    run()
  end

  def down(), do: :ok

  defp run() do
    query =
      from(p in Post,
        where: p.ready_state == ^Post.published() and is_nil(p.published_at)
      )

    query
    |> Repo.all()
    |> Enum.map(fn
      %Post{featured_item: nil, updated_at: dt} = post ->
        post |> Ecto.Changeset.change(published_at: DateTime.to_naive(dt))

      %Post{inserted_at: dt} = post ->
        post |> Ecto.Changeset.change(published_at: DateTime.to_naive(dt))
    end)
    |> Enum.map(&Repo.update!/1)
  end
end
