defmodule Sanbase.Price.Validator do
  use Supervisor

  @gen_servers_count 8

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    gen_servers_count = Keyword.get(opts, :gen_servers_count, @gen_servers_count)

    children =
      for num <- 0..(gen_servers_count - 1) do
        name = String.to_atom("Sanbase.Price.Validator.Node_#{num}")
        {Sanbase.Price.Validator.Node, name: name, number: num}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  def valid_price?(slug, quote_asset, price) do
    GenServer.call(node_name(slug), {:valid_price?, slug, quote_asset, price}, 1000)
  rescue
    _ ->
      # The price validation is nice but not necessary. In case it times out,
      # just ingest the price so it's not lost.
      true
  end

  def update_prices(slug, quote_asset, prices) do
    GenServer.call(node_name(slug), {:update_prices, slug, quote_asset, prices}, 100_000)
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
    "Sanbase.Price.Validator.Node_#{slug_to_number(slug)}" |> String.to_atom()
  end
end
