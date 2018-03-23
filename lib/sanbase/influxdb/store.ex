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

      def import(measurements) do
        # 1 day of 5 min resolution data
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
        |> __MODULE__.execute()
      end

      def create_db() do
        Sanbase.Utils.Config.get(:database)
        |> Instream.Admin.Database.create()
        |> __MODULE__.execute()
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
