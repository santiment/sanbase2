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

      def import(nil) do
        :ok
      end

      def import(%Measurement{} = measurement) do
        :ok =
          measurement
          |> Measurement.convert_measurement_for_import()
          |> __MODULE__.write()
      end

      def import([]) do
        :ok
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
        |> Stream.map(fn data_for_import ->
          :ok = __MODULE__.write(data_for_import)
        end)
        |> Stream.run()
      end

      def delete_by_tag(measurement, tag_key, tag_value) do
        ~s/DELETE from "#{measurement}"
        WHERE #{tag_key} = '#{tag_value}'/
        |> __MODULE__.query()
      end

      def list_measurements() do
        ~s/SHOW MEASUREMENTS/
        |> __MODULE__.query()
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
        |> __MODULE__.execute(method: :post)
      end

      def create_db() do
        Sanbase.Utils.Config.get(:database)
        |> Instream.Admin.Database.create()
        |> __MODULE__.execute(method: :post)
      end

      def last_record(measurement) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time DESC LIMIT 1/
        |> __MODULE__.query()
        |> parse_time_series()
      end

      def last_datetime(measurement) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time DESC LIMIT 1/
        |> __MODULE__.query()
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
        |> __MODULE__.query()
        |> parse_measurement_datetime()
      end

      def last_datetime_with_tag(measurement, tag_name, tag_value) do
        ~s/SELECT * FROM "#{measurement}" ORDER BY time DESC LIMIT 1
        WHERE "#{tag_name}" = #{tag_value}/
        |> __MODULE__.query()
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
        |> __MODULE__.query()
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
      def influx_time(datetime, from_type \\ nil)

      def influx_time(%DateTime{} = datetime, _from_type) do
        DateTime.to_unix(datetime, :nanoseconds)
      end

      def influx_time(datetime, :seconds) when is_integer(datetime) do
        datetime * 1_000_000_000
      end

      def influx_time(datetime, :milliseconds) when is_integer(datetime) do
        datetime * 1_000_000
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
