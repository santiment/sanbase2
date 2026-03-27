defmodule Sanbase.Clickhouse.HistoricalBalance.UtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Clickhouse.HistoricalBalance.Utils

  describe "fill_gaps_last_seen_balance/1" do
    test "fills gaps with last seen balance when has_changed is 0" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-02 00:00:00Z]
      dt3 = ~U[2024-01-03 00:00:00Z]

      input = [
        %{balance: 100.0, has_changed: 1, datetime: dt1},
        %{balance: 0, has_changed: 0, datetime: dt2},
        %{balance: 200.0, has_changed: 1, datetime: dt3}
      ]

      assert Utils.fill_gaps_last_seen_balance(input) == [
               %{balance: 100.0, datetime: dt1},
               %{balance: 100.0, datetime: dt2},
               %{balance: 200.0, datetime: dt3}
             ]
    end

    test "handles all changed values" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-02 00:00:00Z]

      input = [
        %{balance: 50.0, has_changed: 1, datetime: dt1},
        %{balance: 75.0, has_changed: 1, datetime: dt2}
      ]

      assert Utils.fill_gaps_last_seen_balance(input) == [
               %{balance: 50.0, datetime: dt1},
               %{balance: 75.0, datetime: dt2}
             ]
    end

    test "handles all unchanged values — fills with initial 0" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-02 00:00:00Z]

      input = [
        %{balance: 0, has_changed: 0, datetime: dt1},
        %{balance: 0, has_changed: 0, datetime: dt2}
      ]

      assert Utils.fill_gaps_last_seen_balance(input) == [
               %{balance: 0, datetime: dt1},
               %{balance: 0, datetime: dt2}
             ]
    end

    test "handles empty list" do
      assert Utils.fill_gaps_last_seen_balance([]) == []
    end

    test "multiple consecutive gaps are filled with same last seen balance" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-02 00:00:00Z]
      dt3 = ~U[2024-01-03 00:00:00Z]
      dt4 = ~U[2024-01-04 00:00:00Z]

      input = [
        %{balance: 300.0, has_changed: 1, datetime: dt1},
        %{balance: 0, has_changed: 0, datetime: dt2},
        %{balance: 0, has_changed: 0, datetime: dt3},
        %{balance: 0, has_changed: 0, datetime: dt4}
      ]

      assert Utils.fill_gaps_last_seen_balance(input) == [
               %{balance: 300.0, datetime: dt1},
               %{balance: 300.0, datetime: dt2},
               %{balance: 300.0, datetime: dt3},
               %{balance: 300.0, datetime: dt4}
             ]
    end
  end

  describe "maybe_fill_gaps_last_seen_balance/1" do
    test "wraps fill_gaps_last_seen_balance in ok tuple" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-02 00:00:00Z]

      input = [
        %{balance: 100.0, has_changed: 1, datetime: dt1},
        %{balance: 0, has_changed: 0, datetime: dt2}
      ]

      assert Utils.maybe_fill_gaps_last_seen_balance({:ok, input}) ==
               {:ok,
                [
                  %{balance: 100.0, datetime: dt1},
                  %{balance: 100.0, datetime: dt2}
                ]}
    end

    test "passes through errors" do
      assert Utils.maybe_fill_gaps_last_seen_balance({:error, "some error"}) ==
               {:error, "some error"}
    end
  end

  describe "maybe_fill_gaps_last_seen_balance_ohlc/1" do
    test "fills gaps with last seen OHLC values" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-02 00:00:00Z]
      dt3 = ~U[2024-01-03 00:00:00Z]

      input = [
        %{open: 10.0, high: 15.0, low: 8.0, close: 12.0, has_changed: 1, datetime: dt1},
        %{has_changed: 0, datetime: dt2},
        %{open: 20.0, high: 25.0, low: 18.0, close: 22.0, has_changed: 1, datetime: dt3}
      ]

      assert Utils.maybe_fill_gaps_last_seen_balance_ohlc({:ok, input}) ==
               {:ok,
                [
                  %{open: 10.0, high: 15.0, low: 8.0, close: 12.0, datetime: dt1},
                  %{open: 10.0, high: 15.0, low: 8.0, close: 12.0, datetime: dt2},
                  %{open: 20.0, high: 25.0, low: 18.0, close: 22.0, datetime: dt3}
                ]}
    end

    test "initial gap uses zero OHLC values" do
      dt1 = ~U[2024-01-01 00:00:00Z]

      input = [%{has_changed: 0, datetime: dt1}]

      assert Utils.maybe_fill_gaps_last_seen_balance_ohlc({:ok, input}) ==
               {:ok, [%{open: 0, high: 0, low: 0, close: 0, datetime: dt1}]}
    end

    test "passes through errors" do
      assert Utils.maybe_fill_gaps_last_seen_balance_ohlc({:error, "fail"}) ==
               {:error, "fail"}
    end
  end

  describe "maybe_drop_not_needed/2" do
    test "drops entries before the given datetime" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-02 00:00:00Z]
      dt3 = ~U[2024-01-03 00:00:00Z]

      data = [
        %{datetime: dt1, balance: 10.0},
        %{datetime: dt2, balance: 20.0},
        %{datetime: dt3, balance: 30.0}
      ]

      assert Utils.maybe_drop_not_needed({:ok, data}, dt2) ==
               {:ok, [%{datetime: dt2, balance: 20.0}, %{datetime: dt3, balance: 30.0}]}
    end

    test "keeps all entries if all are after the cutoff" do
      dt1 = ~U[2024-01-05 00:00:00Z]
      dt2 = ~U[2024-01-06 00:00:00Z]
      cutoff = ~U[2024-01-01 00:00:00Z]

      data = [%{datetime: dt1, balance: 10.0}, %{datetime: dt2, balance: 20.0}]

      assert Utils.maybe_drop_not_needed({:ok, data}, cutoff) == {:ok, data}
    end

    test "passes through errors" do
      assert Utils.maybe_drop_not_needed({:error, "err"}, ~U[2024-01-01 00:00:00Z]) ==
               {:error, "err"}
    end
  end
end
