defmodule Sanbase.Signal.Behaviour do
  @type slug :: String.t()
  @type selector :: map()
  @type signal :: String.t()
  @type interval :: String.t()
  @type available_data_types :: :timeseries | :histogram | :table
  @type opts :: Keyword.t()

  @type metadata :: %{
          signal: signal,
          min_interval: interval(),
          default_aggregation: atom(),
          available_aggregations: list(atom()),
          available_selectors: list(atom()),
          data_type: available_data_types(),
          complexity_weight: number(),
          is_timebound: boolean()
        }

  @type timeseries_data_point :: %{datetime: Datetime.t(), value: float(), metadata: list(map())}

  @type raw_data_point :: %{
          datetime: Datetime.t(),
          value: float(),
          signal: String.t(),
          slug: String.t(),
          metadata: map()
        }

  @type aggregation :: nil | :any | :sum | :avg | :min | :max | :last | :first | :median

  # Return types
  @type available_signals_result :: {:ok, list(signal)} | {:error, String.t()}

  @type available_slugs_result :: {:ok, list(slug)} | {:error, String.t()}

  @type metadata_result :: {:ok, metadata}

  @type first_datetime_result :: {:ok, DateTime.t()} | {:error, String.t()}

  @type timeseries_data_result :: {:ok, list(timeseries_data_point)} | {:error, String.t()}

  @type aggregated_timeseries_data_result :: {:ok, map()} | {:error, String.t()}

  @type raw_data_result :: {:ok, list(raw_data_point())} | {:error, String.t()}

  # Callbacks
  @callback available_signals() :: list(signal)

  @callback available_signals(selector) :: available_signals_result()

  @callback available_slugs(signal) :: available_slugs_result()

  @callback metadata(signal) :: metadata_result()

  @callback first_datetime(signal, selector | nil) :: first_datetime_result()

  @callback raw_data(
              signals :: :all | list(signal),
              selector :: :all | selector(),
              from :: DateTime.t(),
              to :: DateTime.t()
            ) :: raw_data_result()

  @callback timeseries_data(
              signal :: signal,
              selector :: selector,
              from :: DateTime.t(),
              to :: DateTime.t(),
              interval :: interval,
              opts :: opts
            ) :: timeseries_data_result()

  @callback aggregated_timeseries_data(
              signal :: signal,
              selector :: selector,
              from :: DateTime.t(),
              to :: DateTime.t(),
              opts :: opts
            ) :: aggregated_timeseries_data_result()
end
