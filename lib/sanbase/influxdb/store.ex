defmodule Sanbase.Influxdb.Store do
  @moduledoc """
    Contains common logic for operating working with InfluxDB.
    This module should be used be declaring:
    ```
    use Sanbase.Influxdb.Store
    ```
  """

  defmacro __using__(_options \\ []) do
    quote do
      use Instream.Connection, otp_app: :sanbase
      require Sanbase.Utils.Config
      require Logger

      alias Sanbase.Influxdb.Measurement
      @query_timeout 10_000
      @pool_timeout 10_000

      defp post(query) do
        query
        |> __MODULE__.execute(
          method: :post,
          query_timeout: @query_timeout,
          pool_timeout: @pool_timeout
        )
      end

      defp get(query) do
        query
        |> __MODULE__.query(query_timeout: @query_timeout, pool_timeout: @pool_timeout)
      end

      defp write_data(data) do
        data |> __MODULE__.write(query_timeout: @query_timeout, pool_timeout: @pool_timeout)
      end

      def import(no_data) when is_nil(no_data) or no_data == [], do: :ok

      def import(%Measurement{} = measurement) do
        :ok =
          measurement
          |> Measurement.convert_measurement_for_import()
          |> write_data()
      end

      def import({:error, reason} = err_tuple) do
        Logger.warn(
          "Store.import/1 from #{__MODULE__} called with an error tuple: #{inspect(err_tuple)}"
        )

        err_tuple
      end

      def import(measurements) do
        measurements
        |> Stream.map(&Measurement.convert_measurement_for_import/1)
        |> Stream.reject(&is_nil/1)
        |> Stream.chunk_every(2500)
        |> Stream.map(fn data ->
          :ok = write_data(data)
        end)
        |> Stream.run()
      end

      def delete_by_tag(measurement, tag_key, tag_value) do
        ~s/DELETE from "#{measurement}"
        WHERE #{tag_key} = '#{tag_value}'/
        |> post()
      end

      def list_measurements() do
        ~s/SHOW MEASUREMENTS/
        |> get()
        |> parse_measurements_list()
      end

      def list_measurements!() do
        case list_measurements() do
          {:ok, measurements} -> measurements
          {:error, error} -> raise(error)
        end
      end

      def drop_measurement(measurement_name) do
        ~s/DROP MEASUREMENT "#{measurement_name}"/
        |> post()
      end

      def create_db() do
        Sanbase.Utils.Config.get(:database)
        |> Instream.Admin.Database.create()
        |> post()
      end

      def last_record(measurement) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time DESC LIMIT 1/
        |> get()
        |> parse_time_series()
      end

      def last_datetime(measurement) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time DESC LIMIT 1/
        |> get()
        |> parse_measurement_datetime()
      end

      def last_datetime!(measurement) do
        case last_datetime(measurement) do
          {:ok, datetime} -> datetime
          {:error, error} -> raise(error)
        end
      end

      def last_datetime_with_tag(measurement, tag_name, tag_value) when is_binary(tag_value) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time DESC LIMIT 1
        WHERE "#{tag_name}" = '#{tag_value}'/
        |> get()
        |> parse_measurement_datetime()
      end

      def last_datetime_with_tag(measurement, tag_name, tag_value) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time DESC LIMIT 1
        WHERE "#{tag_name}" = #{tag_value}/
        |> get()
        |> parse_measurement_datetime()
      end

      def last_datetime_with_tag!(measurement, tag_name, tag_value) do
        case last_datetime_with_tag(measurement, tag_name, tag_value) do
          {:ok, datetime} -> datetime
          {:error, error} -> raise(error)
        end
      end

      def first_datetime(measurement) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time ASC LIMIT 1/
        |> get()
        |> parse_measurement_datetime()
      end

      def first_datetime!(measurement) do
        case first_datetime(measurement) do
          {:ok, datetime} -> datetime
          {:error, error} -> raise(error)
        end
      end

      @doc ~s"""
        Returns a list of measurement names that are used internally and should not be exposed.
        Should be overridden if the Store module uses internal measurements
      """
      def internal_measurements() do
        {:ok, []}
      end

      defoverridable internal_measurements: 0

      @doc ~s"""
        Returns a list of all measurements except the internal ones
      """
      def public_measurements() do
        with {:ok, all_measurements} <- list_measurements(),
             {:ok, internal_measurements} <- internal_measurements() do
          {
            :ok,
            all_measurements
            |> Enum.reject(fn x -> Enum.member?(internal_measurements, x) end)
          }
        end
      end

      @doc ~s"""
        Transforms the `datetime` parammeter to the internally used datetime format
        which is timestamp in nanoseconds
      """
      def influx_time(datetime, from_type \\ :nanosecond)

      def influx_time(datetime, :second) when is_integer(datetime) do
        datetime * 1_000_000_000
      end

      def influx_time(datetime, :millisecond) when is_integer(datetime) do
        datetime * 1_000_000
      end

      def influx_time(%DateTime{} = datetime, :nanosecond) do
        DateTime.to_unix(datetime, :nanosecond)
      end

      def parse_time_series(%{results: [%{error: error}]}) do
        {:error, error}
      end

      @doc ~s"""
        Parse the values from a time series into a list of list. Each list
        begins with the datetime, parsed from iso8601 into %DateTime{} format.
        The rest of the values in the list are not changed.
      """
      def parse_time_series(%{
            results: [
              %{
                series: [
                  %{
                    values: values
                  }
                ]
              }
            ]
          }) do
        result =
          values
          |> Enum.map(fn [iso8601_datetime | rest] ->
            {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)
            [datetime | rest]
          end)

        {:ok, result}
      end

      def parse_time_series(_) do
        {:ok, []}
      end

      # Private functions

      defp parse_measurements_list(%{results: [%{error: error}]}), do: {:error, error}

      defp parse_measurements_list(%{
             results: [
               %{
                 series: [
                   %{
                     values: measurements
                   }
                 ]
               }
             ]
           }) do
        {:ok, measurements |> Enum.map(&Kernel.hd/1)}
      end

      defp parse_measurement_datetime(%{results: [%{error: error}]}) do
        {:error, error}
      end

      defp parse_measurement_datetime(%{
             results: [
               %{
                 series: [
                   %{
                     values: [[iso8601_datetime | _] | _rest]
                   }
                 ]
               }
             ]
           }) do
        {:ok, datetime, _} = DateTime.from_iso8601(iso8601_datetime)

        {:ok, datetime}
      end

      defp parse_measurement_datetime(_) do
        {:ok, nil}
      end
    end
  end
end
