defmodule Sanbase.TestSetupService do
  @moduledoc ~s"""
  Module for fast checking if a slug is existing.

  The slugs are stored in an ETS table and the check is done via :ets.lookup/2.
  This is faster than caching all slugs, retrieving them in the caller process and
  checking if the slug is in the list.
  """

  use GenServer

  @ets_table :__test_only_ets_table__
  def get_ets_table_name, do: @ets_table

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(_opts) do
    ets_table =
      :ets.new(@ets_table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    initial_state = %{ets_table: ets_table}

    {:ok, initial_state}
  end
end
