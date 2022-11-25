defmodule Sanbase.Market do
  use Ecto.Schema

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.{Project, Project.SourceSlugMapping}

  schema "asset_exchange_pairs" do
    field(:base_asset, :string)
    field(:quote_asset, :string)
    field(:exchange, :string)
    field(:source, :string)

    timestamps()
  end

  def list_exchanges() do
    result =
      from(
        pair in __MODULE__,
        group_by: pair.exchange,
        select: %{
          exchange: pair.exchange,
          pairs_count: count(pair.id),
          assets_count: count(pair.base_asset, :distinct)
        }
      )
      |> Repo.all()

    {:ok, result}
  end

  def slugs_by_exchange_any_of(exchanges) when is_list(exchanges) do
    exchanges = Enum.map(exchanges, &String.downcase/1)

    result =
      from([pair: pair, ssm: ssm, project: project] in base_query(),
        where: fragment("lower(?)", pair.exchange) in ^exchanges,
        select: project.slug,
        distinct: true
      )
      |> Repo.all()

    {:ok, result}
  end

  def slugs_by_exchange_all_of(exchanges) when is_list(exchanges) do
    exchanges = Enum.map(exchanges, &String.downcase/1)

    result =
      from([pair: pair, ssm: ssm, project: project] in base_query(),
        select: project.slug,
        group_by: project.slug,
        having: fragment("array_agg(DISTINCT(lower(?))) @> (?)", pair.exchange, ^exchanges),
        distinct: true
      )
      |> Repo.all()

    {:ok, result}
  end

  def exchanges_per_slug(slugs) when is_list(slugs) do
    from([pair: pair, ssm: ssm, project: project] in base_query(),
      where: project.slug in ^slugs,
      group_by: project.slug,
      select: {project.slug, fragment("array_agg(DISTINCT ?)", pair.exchange)}
    )
    |> Repo.all()
  end

  def exchanges_count_per_slug(slugs) when is_list(slugs) do
    from([pair: pair, ssm: ssm, project: project] in base_query(),
      where: project.slug in ^slugs,
      group_by: project.slug,
      select: {project.slug, fragment("count(DISTINCT ?)", pair.exchange)}
    )
    |> Repo.all()
  end

  defp base_query() do
    from(pair in __MODULE__,
      as: :pair,
      inner_join: ssm in SourceSlugMapping,
      as: :ssm,
      on: ssm.slug == pair.base_asset and ssm.source == "cryptocompare",
      inner_join: project in Project,
      as: :project,
      on: ssm.project_id == project.id
    )
  end
end
