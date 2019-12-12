defmodule Sanbase.Exchanges.MarketPairMapping do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @default_source "coinmarketcap"

  schema "exchange_market_pair_mappings" do
    field(:exchange, :string, null: false)
    field(:market_pair, :string, null: false)
    field(:from_ticker, :string, null: false)
    field(:to_ticker, :string, null: false)
    field(:from_slug, :string, null: false)
    field(:to_slug, :string, null: false)
    field(:source, :string, null: false)

    timestamps()
  end

  @doc false
  def changeset(market_pair_mapping, attrs) do
    market_pair_mapping
    |> cast(attrs, [
      :exchange,
      :market_pair,
      :from_ticker,
      :to_ticker,
      :from_slug,
      :to_slug,
      :source
    ])
    |> validate_required([
      :exchange,
      :market_pair,
      :from_ticker,
      :to_ticker,
      :from_slug,
      :to_slug,
      :source
    ])
  end

  def get_slugs_pair_by(exchange, market_pair, source \\ @default_source) do
    from(
      emp in __MODULE__,
      where:
        emp.exchange == ^exchange and emp.market_pair == ^market_pair and emp.source == ^source,
      select: {emp.from_slug, emp.to_slug}
    )
    |> Sanbase.Repo.one()
    |> case do
      nil -> {nil, nil}
      {from_sulg, to_slug} -> {from_sulg, to_slug}
    end
  end
end
