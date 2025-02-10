defmodule Sanbase.Interaction.DateTime do
  @moduledoc false
  @ets_table :unique_interaction_datetime_counter

  def start_ets do
    spawn(fn ->
      :ets.new(@ets_table, [
        :set,
        :public,
        :named_table
      ])

      # Infinite sleep so the process does not die and the ETS table lives
      # throughout the test
      Process.sleep(:infinity)
    end)

    # Wait until the table is ready
    for _ <- 1..5, do: if(:ets.whereis(@ets_table) == :undefined, do: Process.sleep(100))
  end

  def utc_now do
    if :ets.whereis(@ets_table) == :undefined, do: start_ets()

    counter = :ets.update_counter(@ets_table, :counter, {2, 1}, {:counter, 1})

    DateTime.add(DateTime.utc_now(), -counter)
  end

  def to_naive(dt), do: DateTime.to_naive(dt)
end
