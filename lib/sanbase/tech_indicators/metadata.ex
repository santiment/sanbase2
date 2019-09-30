defmodule Sanbase.TechIndicators.Metadata do
  def get(_metric) do
    %{
      min_interval: "5m",
      default_aggregation: :sum
    }
  end

  def first_datetime(<<"professional_traders_chat", _rest::binary>>), do: ~U[2018-02-09 00:00:00Z]
  def first_datetime(<<"telegram", _rest::binary>>), do: ~U[2016-03-29 00:00:00Z]
  def first_datetime(<<"twitter", _rest::binary>>), do: ~U[2018-02-13 00:00:00Z]
  def first_datetime(<<"reddit", _rest::binary>>), do: ~U[2016-01-01 00:00:00Z]
  def first_datetime(<<"discord", _rest::binary>>), do: ~U[2016-05-21 00:00:00Z]
  def first_datetime(<<"bitcointalk", _rest::binary>>), do: ~U[2009-11-22 00:00:00Z]
end
