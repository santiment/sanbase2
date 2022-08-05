defmodule Sanbase.BlockchainAddress.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2, rename_map_keys: 2]

  alias Sanbase.Balance
  alias Sanbase.Model.Project
  alias Sanbase.BlockchainAddress

  @aggregations [:sum, :ohlc]
  @default_aggregation :sum

  @timeseries_metrics ["historical_balance", "historical_balance_changes"]
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  # plan related - the plan is upcase string
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, "FREE"} end)

  # restriction related - the restriction is atom :free or :restricted
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

  @free_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end)
                |> Enum.map(&elem(&1, 0))
  @restricted_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end)
                      |> Enum.map(&elem(&1, 0))

  @required_selectors Enum.into(@metrics, %{}, &{&1, [[:blockchain_address], [:slug]]})
  @default_complexity_weight 0.3

  @human_readable_name_map %{
    "historical_balance" => "Historical Balance",
    "historical_balance_changes" => "Historical Balance Changes"
  }

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_table_metrics(), do: @table_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour

  def available_metrics(%{address: _address}), do: []

  def available_metrics(%{contract_address: contract_address}) do
    Sanbase.Metric.Utils.available_metrics_for_contract(__MODULE__, contract_address)
  end

  def available_metrics(%{slug: slug}) do
    with {:ok, _, _, infrastructure} <- Project.contract_info_infrastructure_by_slug(slug),
         <<_::binary>> <- BlockchainAddress.blockchain_from_infrastructure(infrastructure) do
      {:ok, @metrics}
    else
      _ -> {:ok, []}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    infrastructures = Balance.supported_infrastructures()
    {:ok, Project.List.slugs_by_infrastructure(infrastructures)}
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    available_slugs()
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, %{slug: slug, blockchain_address: %{address: address}})
      when metric in @metrics do
    Balance.first_datetime(address, slug)
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(metric, %{slug: _slug, blockchain_address: %{address: _address}})
      when metric in @metrics do
    # There is no nice value we can put here
    {:ok, DateTime.utc_now()}
  end

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: []

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric), do: {:ok, Map.get(@human_readable_name_map, metric)}
  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "5m",
       default_aggregation: @default_aggregation,
       available_aggregations: @aggregations,
       available_selectors: [:blockchain_address, :slug],
       required_selectors: Map.get(@required_selectors, metric, []),
       data_type: :timeseries,
       complexity_weight: @default_complexity_weight
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(
        "historical_balance",
        %{slug: slug, blockchain_address: %{address: address}},
        from,
        to,
        interval,
        opts
      ) do
    case Keyword.get(opts, :aggregation) do
      :ohlc ->
        Sanbase.Balance.historical_balance_ohlc(address, slug, from, to, interval)
        |> maybe_apply_function(fn elem ->
          %{
            datetime: elem.datetime,
            open: elem.open_balance,
            close: elem.close_balance,
            high: elem.high_balance,
            low: elem.low_balance
          }
        end)

      _ ->
        Sanbase.Balance.historical_balance(address, slug, from, to, interval)
        |> rename_map_keys(old_key: :balance, new_key: :value)
    end
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(
        "historical_balance_changes",
        %{slug: slug, blockchain_address: %{address: address}},
        from,
        to,
        interval,
        _opts
      ) do
    Sanbase.Balance.historical_balance_changes(address, slug, from, to, interval)
    |> rename_map_keys(old_key: :balance, new_key: :value)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, _selector, _from, _to, _opts) do
    not_implemented_error("aggregated timeseries data", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def addresses_by_filter("historical_balance", %{slug: slug}, operator, threshold, opts) do
    Sanbase.Balance.addresses_by_filter(slug, operator, threshold, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def addresses_by_filter(metric, _selector, _operator, _threshold, _opts) do
    not_implemented_error("addresses_by_filter", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def addresses_order(metric, _selector, _direction, _opts) do
    not_implemented_error("addresses_order", metric)
  end

  # Private functions
  defp not_implemented_error(function, metric) do
    {:error, "The #{function} function is not implemented for #{metric}"}
  end
end
