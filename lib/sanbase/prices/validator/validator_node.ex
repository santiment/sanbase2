defmodule Sanbase.Price.Validator.Node do
  @moduledoc ~s"""
  Check if a new realtime price is valid or is and outlier.
  """

  use GenServer
  @max_prices 6

  alias Sanbase.Model.Project
  alias Sanbase.Price

  require Sanbase.Utils.Config, as: Config

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

  def enabled?() do
    with true <- Sanbase.ClickhouseRepo.enabled?(),
         true <- Config.module_get_boolean(Sanbase.Price.Validator, :enabled) do
      true
    else
      _ -> false
    end
  end

  def init(opts) do
    number = Keyword.fetch!(opts, :number)

    case enabled?() do
      false ->
        # If the ClickhouseRepo is disabled do not initialize anything. This is the
        # flow only in dev/test environment. In case of empty state, the price is
        # considered valid.
        {:ok, %{}}

      true ->
        slugs =
          Sanbase.Cache.get_or_store(:all_project_slugs_include_hidden_no_preload, fn ->
            Project.List.projects_slugs(include_hidden: true, preload?: false)
          end)
          |> Enum.filter(&(Price.Validator.slug_to_number(&1) == number))

        {:ok, latest_prices} = Price.latest_prices_per_slug(slugs, @max_prices)

        state = latest_prices |> Map.put(:number, number)

        {:ok, state}
    end
  end

  def handle_call(:clean_state, _from, _state) do
    {:reply, :ok, %{}}
  end

  # Validate the price by comparing it to the latest @max_prices prices.
  # A price is considered invalid if it does not match any of the checks
  # in the with pipeline. Currently the only check is done for outliers.
  # See the documentation of hte `price_outlier?/5` function for more info.
  def handle_call({:valid_price?, slug, quote_asset, price}, _from, state) do
    key = {slug, quote_asset}

    case Map.get(state, key, []) do
      [] ->
        {:reply, true, Map.put(state, key, [price])}

      prices ->
        with false <- price_outlier?(slug, quote_asset, price, prices, allowed_times_diff: 30) do
          # Keep the in memory prices to a maximum of @max_prices
          prices = maybe_drop_oldest_price(prices) ++ [price]
          state = Map.put(state, key, prices)

          {:reply, true, state}
        else
          {:error, _} = error ->
            {:reply, error, state}
        end
    end
  end

  # If there are less than @max_prices prices, return as is
  # If there are @max_prices in the list, drop the oldest price as we'll add the
  # newest price to the list. This is executed only if the new price that is
  # validated is accepted
  defp maybe_drop_oldest_price(prices) when length(prices) < @max_prices, do: prices
  defp maybe_drop_oldest_price([_ | prices]), do: prices

  # A price is an outlier if it is a given amount of times bigger or smaller
  # than the average of the in memory stored prices.
  defp price_outlier?(_slug, _quote_asset, _price, [], _opts), do: false

  defp price_outlier?(slug, quote_asset, price, prices, opts) do
    allowed_times_diff = Keyword.fetch!(opts, :allowed_times_diff)

    count = Enum.count(prices)
    avg_price = Enum.sum(prices) / count

    cond do
      price > avg_price and price > avg_price * allowed_times_diff ->
        ratio = Float.round(price / avg_price, 2)

        {:error,
         """
         The #{slug} #{quote_asset} price #{price} is more than #{allowed_times_diff} \
         times (#{ratio}) bigger than the average of the last #{count} prices - #{avg_price}
         """}

      price < avg_price and price * allowed_times_diff < avg_price ->
        ratio = Float.round(avg_price / price, 2)

        {:error,
         """
         The #{slug} #{quote_asset} price #{price} is more than #{allowed_times_diff} \
         times (#{ratio}) smaller than the average of the last #{count} prices - #{avg_price}
         """}

      true ->
        false
    end
  end
end
