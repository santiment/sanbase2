defmodule Sanbase.Exchanges.MarketPairMapping do
  use Ecto.Schema
  import Ecto.Changeset

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
end
