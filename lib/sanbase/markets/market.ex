defmodule Sanbase.Market do
  use Ecto.Schema

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Model.{Project, Project.SourceSlugMapping}

  schema "asset_exchange_pairs" do
    field(:base_asset, :string)
    field(:quote_asset, :string)
    field(:exchange, :string)
    field(:source, :string)
    field(:last_update, :utc_datetime)

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

  def slugs_by_exchange(exchange) when is_binary(exchange) do
    exchange = String.downcase(exchange)

    result =
      from(pair in __MODULE__,
        inner_join: ssm in SourceSlugMapping,
        on: ssm.slug == pair.base_asset,
        inner_join: project in Project,
        on: ssm.project_id == project.id,
        where: fragment("lower(?)", pair.exchange) == ^exchange,
        select: project.slug,
        distinct: true
      )
      |> Repo.all()

    {:ok, result}
  end

  def slugs_by_exchange(exchanges) when is_list(exchanges) do
    exchanges = Enum.map(exchanges, &String.downcase/1)

    result =
      from(pair in __MODULE__,
        inner_join: ssm in SourceSlugMapping,
        on: ssm.slug == pair.base_asset,
        inner_join: project in Project,
        on: ssm.project_id == project.id,
        where: fragment("lower(?)", pair.exchange) in ^exchanges,
        select: project.slug,
        distinct: true
      )
      |> Repo.all()

    {:ok, result}
  end
end
