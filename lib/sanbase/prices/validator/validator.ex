defmodule Sanbase.Price.Validator do
  @moduledoc ~s"""
  Validates new realtime prices by comparing them to its previous values.

  This validators starts 8 GenServers, each one handling a portion of the
  slugs. Every slug is dispatched to its proper GenServer, which handles
  all the state and valiadtions.
  More more info see the  Sanbase.Price.Validator.Node module and its
  documentation
  """
  use Supervisor

  @gen_servers_count 8

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_opts) do
    children =
      for num <- 0..(@gen_servers_count - 1) do
        # credo:disable-for-next-line
        name = String.to_atom("Sanbase.Price.Validator.Node_#{num}")
        {Sanbase.Price.Validator.Node, name: name, number: num}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  def clean_state() do
    for num <- 0..(@gen_servers_count - 1) do
      # credo:disable-for-next-line
      name = String.to_atom("Sanbase.Price.Validator.Node_#{num}")
      :ok = GenServer.call(name, :clean_state)
    end
  end

  @doc ~s"""
  Validate a new realtime price for a slug/currency pair. If the price is valid
  `true` is returned, otherwise `{:error, reason}` is returned.
  See the Sanbase.Price.Validator.Node module for more info.
  """
  @spec valid_price?(String.t(), String.t(), float()) :: true | {:error, String.t()}
  def valid_price?(slug, quote_asset, price) when quote_asset in ["BTC", "USD"] do
    GenServer.call(node_name(slug), {:valid_price?, slug, quote_asset, price}, 1000)
  rescue
    _ ->
      # The price validation is nice but not necessary. In case it times out,
      # just ingest the price so it's not lost.
      true
  end

  def slug_to_number(slug) do
    :erlang.phash2(slug, @gen_servers_count)
  end

  defp node_name(slug) do
    # credo:disable-for-next-line
    "Sanbase.Price.Validator.Node_#{slug_to_number(slug)}" |> String.to_atom()
  end
end
