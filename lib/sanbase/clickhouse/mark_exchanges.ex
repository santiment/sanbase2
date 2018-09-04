defmodule Sanbase.Clickhouse.MarkExchanges do
  @moduledoc ~s"""
  Used to transform a list of transactions in the form of

  `[
    %{
      from_address: from,
      to_address: to,
      ...
    }
  ]`

  into a list of transactions where
  addresses have a flag wheter or not they are an exchange address:
  `[
    %{
      from_address:
      %{
        address: from,
        is_exchange: false
        },
      to_address: %{
        address: to,
        is_exchange: true
      },
      ...
    }
  ]`

  This module is tightly coupled with the format of the input.
  The user of this module is tightly coupled with the output of the function.
  """

  use GenServer
  require Sanbase.Utils.Config, as: Config

  @refresh_interval_min 10
  @name :mark_exchange_wallets_gen_server

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  def init(:ok) do
    {:ok, %{}, {:continue, :set_state}}
  end

  def handle_continue(:set_state, _) do
    exchanges =
      Sanbase.Model.ExchangeEthAddress.list_all()
      |> MapSet.new()

    new_state = Map.put(%{}, :exchange_wallets_set, exchanges)
    new_state = Map.put(new_state, :updated_at, Timex.now())

    {:noreply, new_state}
  end

  @doc ~s"""

  """
  def mark_exchange_wallets(transactions) do
    GenServer.call(@name, :update_state_if_staled)
    GenServer.call(@name, {:mark_exchange_wallets, transactions})
  end

  def handle_call(
        {:mark_exchange_wallets, transactions},
        _from,
        %{exchange_wallets_set: exchanges} = state
      ) do
    marked_exchange_transactions =
      transactions
      |> Enum.map(fn %{from_address: from, to_address: to} = transaction ->
        %{
          transaction
          | from_address: %{
              address: from,
              is_exchange: MapSet.member?(exchanges, from)
            },
            to_address: %{
              address: to,
              is_exchange: MapSet.member?(exchanges, to)
            }
        }
      end)

    {:reply, marked_exchange_transactions, state}
  end

  def handle_call(:update_state_if_staled, _from, %{updated_at: updated_at} = state) do
    if Timex.diff(Timex.now(), updated_at, :minutes) >= @refresh_interval_min do
      {:reply, :ok, state, {:continue, :set_state}}
    else
      {:reply, :ok, state}
    end
  end

  @doc false
  def add_exchange_wallets(wallets) when is_list(wallets) do
    # Used to add new exchange wallet addresses. Used only from within tests
    GenServer.call(@name, {:add_exchange_wallets, wallets})
  end

  @doc false
  def handle_call(
        {:add_exchange_wallets, wallets},
        _from,
        %{exchange_wallets_set: exchanges} = state
      ) do
    new_state = %{state | exchange_wallets_set: MapSet.union(exchanges, MapSet.new(wallets))}
    {:reply, :ok, new_state}
  end
end
