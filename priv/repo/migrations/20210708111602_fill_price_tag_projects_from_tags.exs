defmodule Sanbase.Repo.Migrations.FillPriceTagProjectsFromTags do
  use Ecto.Migration
  import Ecto.Query

  def up do
    setup()
    import Ecto.Query

    posts =
      from(p in Sanbase.Insight.Post, preload: [:tags])
      |> Sanbase.Repo.all()
      |> Enum.reject(&(&1.tags == [] or not is_nil(&1.price_chart_project_id)))

    first_tags = posts |> Enum.map(fn %{tags: [first_tag | _]} -> first_tag.name end)

    ticker_to_project_map =
      Sanbase.Model.Project.List.by_field(first_tags, :ticker)
      |> Map.new(fn %{ticker: ticker} = project -> {ticker, project} end)

    posts
    |> Enum.with_index()
    |> Enum.reduce(
      Ecto.Multi.new(),
      fn {post, offset}, multi ->
        first_tag = List.first(post.tags) |> Map.get(:name)

        case Map.get(ticker_to_project_map, first_tag) do
          %Sanbase.Model.Project{} = project ->
            changeset =
              post
              |> Sanbase.Insight.Post.update_changeset(%{price_chart_project_id: project.id})

            Ecto.Multi.update(multi, offset, changeset, on_conflict: :nothing)

          _ ->
            multi
        end
      end
    )
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, _result} -> :ok
      {:error, _name, error, _changes_so_far} -> {:error, error}
    end
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Application.ensure_all_started(:stripity_stripe)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
