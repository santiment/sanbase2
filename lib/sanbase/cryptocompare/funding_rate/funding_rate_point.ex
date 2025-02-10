defmodule Sanbase.Cryptocompare.FundingRatePoint do
  @moduledoc false
  @fields [
    :market,
    :instrument,
    :mapped_instrument,
    :quote_currency,
    :settlement_currency,
    :contract_currency,
    :close,
    :timestamp
  ]
  defstruct @fields

  def new(map) when is_map(map) do
    struct!(__MODULE__, Map.take(map, @fields))
  end

  def json_kv_tuple(%__MODULE__{} = point) do
    point = Map.from_struct(point)

    key = Enum.join([point.market, point.mapped_instrument, point.timestamp], "_")

    {key, Jason.encode!(point)}
  end
end
