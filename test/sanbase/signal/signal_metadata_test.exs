defmodule Sanbase.SignalMetadataTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory, only: [rand_str: 0]

  alias Sanbase.Signal

  test "can fetch metadata for all available signals" do
    signal = Signal.available_signals()
    results = for signal <- signal, do: Signal.metadata(signal)
    assert Enum.all?(results, &match?({:ok, _}, &1))
  end

  test "cannot fetch metadata for not available signals" do
    rand_signals = Enum.map(1..100, fn _ -> rand_str() end)
    rand_signals = rand_signals -- Signal.available_signals()

    results = for signal <- rand_signals, do: Signal.metadata(signal)

    assert Enum.all?(results, &match?({:error, _}, &1))
  end

  test "metadata properties" do
    signals = Signal.available_signals()
    aggregations = Signal.available_aggregations()

    for signal <- signals do
      {:ok, metadata} = Signal.metadata(signal)
      assert metadata.default_aggregation in aggregations
      assert metadata.min_interval == "5m"
    end
  end
end
