defmodule Sanbase.Repo.Migrations.FillPriceChartProjectFromTags do
  use Ecto.Migration

  def up do
    setup()
    import Ecto.Query

    posts =
      from(p in Sanbase.Insight.Post, preload: [:tags])
      |> Sanbase.Repo.all()
      |> Enum.reject(&(&1.tags == []))

    first_tags = posts |> Enum.map(fn %{tags: [first_tag | _]} -> first_tag.name end)

    ticker_to_project_map =
      Sanbase.Model.Project.List.by_field(first_tags, :ticker)
      |> Map.new(fn %{ticker: ticker} = project -> {ticker, project} end)

    now = Timex.now()

    updated_post_structs =
      Enum.map(posts, fn post ->
        first_tag = List.first(post.tags) |> Map.get(:name)

        case Map.get(ticker_to_project_map, first_tag) do
          %Sanbase.Model.Project{} = project ->
            Sanbase.Insight.Post.update_changeset(post, %{
              price_chart_project_id: project.id,
              updated_at: now
            })
            |> Sanbase.Repo.update()

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
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
