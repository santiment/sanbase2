defmodule Sanbase.Price.Validator.Node do
  use GenServer
  @max_prices 6

  alias Sanbase.Model.Project
  alias Sanbase.Price

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    number = Keyword.fetch!(opts, :number)

    slugs =
      Sanbase.Cache.get_or_store(:all_project_slugs_include_hidden_no_preload, fn ->
        Project.List.projects_slugs(include_hidden: true, preload?: false)
      end)
      |> Enum.filter(&(Price.Validator.slug_to_number(&1) == number))

    {:ok, latest_prices} = Price.latest_prices_per_slug(slugs, @max_prices)

    state = latest_prices |> Map.put(:number, number)

    {:ok, state}
  end

  def handle_call({:valid_price?, slug, quote_asset, price}, _from, state) do
    key = {slug, quote_asset}

    case Map.get(state, key, []) do
      [] ->
        {:reply, true, Map.put(state, key, [price])}

      prices ->
        with false <- price_outlier?(slug, quote_asset, price, prices, allowed_times_diff: 5) do
          prices = maybe_drop_oldest_price(prices) ++ [price]

          state = Map.put(state, key, prices)

          {:reply, true, state}
        else
          {:error, _} = error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:update_prices, slug, quote_asset, prices}, _from, state) do
    {:reply, :ok, Map.put(state, {slug, quote_asset}, prices)}
  end

  # If there are less than @max_prices prices, return as is
  # If there are @max_prices in the list, drop the oldest price as we'll add the
  # newest price to the list. This is executed only if the new price that is
  # validated is accepted
  defp maybe_drop_oldest_price(prices) when length(prices) < @max_prices, do: prices
  defp maybe_drop_oldest_price([_ | prices]), do: prices

  defp price_outlier?(_slug, _quote_asset, _price, [], _opts), do: false

  defp price_outlier?(slug, quote_asset, price, prices, opts) do
    allowed_times_diff = Keyword.fetch!(opts, :allowed_times_diff)

    count = Enum.count(prices)
    avg_price = Enum.sum(prices) / count

    cond do
      price > avg_price and price > avg_price * allowed_times_diff ->
        {:error,
         """
         The #{slug} #{quote_asset} price #{price} is more than #{allowed_times_diff} times bigger than the \
         average of the last #{count} prices - #{avg_price}
         """}

      price < avg_price and price * allowed_times_diff < avg_price ->
        {:error,
         """
         The #{slug} #{quote_asset} price #{price} is more than #{allowed_times_diff} times bigger than the \
         average of the last #{count} prices - #{avg_price}
         """}

      true ->
        false
    end
  end
end
