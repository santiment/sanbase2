defmodule Sanbase.Etherbi.EtherbiGenServer do
  @moduledoc ~S"""
    This module is a GenServer that periodically sends requests to etherbi API.

    It requires that there is module `MOD.Store` where `MOD` is the name of the module
    that uses the EtherbiFetcher. For now all modules will use InfluxDB. In the future
    if there is need for not having an InfluxDB this module could be reworked and
    inject different behaviour based on arguments passed via `options` in the `__using__/1`
    macro

    It requires a single callback `work/0` to be implemented. It is called every

    It requires a module attribute `@default_update_interval` to be defined
  """
  @callback work() :: any()

  defmacro __using__(_options \\ []) do
    quote do
      use GenServer

      require Logger
      require Sanbase.Utils.Config

      require Ecto.Query

      @doc ~s"""
        Starts the GenServer
      """
      @spec start_link(any()) :: { :ok, pid }
      def start_link(_state) do
        GenServer.start_link(__MODULE__, :ok)
      end

      @doc ~s"""
        Requires the existence of MOD.Store where MOD is the module this is used.
        If `:sync_enabled` is true, creates an influxdb table if it is missing and
        starts the genserver
      """
      @spec init(any()) :: {:ok, any()} | :ignore
      def init(_state) do
        if Sanbase.Utils.Config.get(:sync_enabled, false) do
          __MODULE__.Store.create_db()

          update_interval_ms =
            Sanbase.Utils.Config.get(:update_interval, @default_update_interval)

          GenServer.cast(self(), :sync)
          {:ok, %{update_interval_ms: update_interval_ms}}
        else
          :ignore
        end
      end

      @doc ~s"""
      Requires the function `work/0` to be available and calls it at the given period of time
      """
      @spec handle_cast(:sync, map()) :: {:noreply, map()}
      def handle_cast(
            :sync,
            %{update_interval_ms: update_interval_ms} = state
          ) do
        work()
        Process.send_after(self(), {:"$gen_cast", :sync}, update_interval_ms)
        {:noreply, state}
      end

      @doc ~s"""
      TODO
      """
      @spec build_token_decimals_map() :: map()
      def build_token_decimals_map() do
        query =
          Ecto.Query.from(
            p in Sanbase.Model.Project,
            where: not is_nil(p.token_decimals),
            select: %{ticker: p.ticker, token_decimals: p.token_decimals}
          )

        Sanbase.Repo.all(query)
        |> Enum.map(fn %{ticker: ticker, token_decimals: token_decimals} ->
          {ticker, :math.pow(10, token_decimals)}
        end)
        |> Map.new()
      end
    end
  end
end