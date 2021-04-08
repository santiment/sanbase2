defmodule Sanbase.Signal.AvailableSignalsTest do
  use ExUnit.Case, async: true

  test "available signals" do
    available_signals =
      Sanbase.Signal.available_signals()
      |> Enum.sort()

    expected_available_signals =
      [
        "dai_mint",
        "old_coins_moved",
        "large_transactions",
        "large_exchange_deposit",
        "large_exchange_withdrawal"
      ]
      |> Enum.sort()

    assert available_signals == expected_available_signals
  end
end
