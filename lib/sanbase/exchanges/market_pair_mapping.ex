defmodule Sanbase.Exchanges.MarketPairMapping do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @default_source "coinmarketcap"

  schema "exchange_market_pair_mappings" do
    field(:exchange, :string)
    field(:market_pair, :string)
    field(:from_ticker, :string)
    field(:to_ticker, :string)
    field(:from_slug, :string)
    field(:to_slug, :string)
    field(:source, :string)

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
    Sanbase.Repo.one(
      from(emp in __MODULE__,
        where: emp.exchange == ^exchange and emp.market_pair == ^market_pair and emp.source == ^source,
        select: %{from_slug: emp.from_slug, to_slug: emp.to_slug}
      )
    )
  end

  def slugs_to_exchange_market_pair(exchange, from_slug, to_slug, source \\ @default_source) do
    Sanbase.Repo.one(
      from(emp in __MODULE__,
        where:
          emp.exchange == ^exchange and emp.from_slug == ^from_slug and emp.to_slug == ^to_slug and emp.source == ^source,
        select: %{market_pair: emp.market_pair, from_ticker: emp.from_ticker, to_ticker: emp.to_ticker}
      )
    )
  end
end
