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

      alias Sanbase.Influxdb.Measurement

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
        |> Stream.chunk_every(288)
        |> Stream.map(fn data_for_import ->
             :ok = __MODULE__.write(data_for_import)
           end)
        |> Stream.run()
      end

      def list_measurements!() do
        "SHOW MEASUREMENTS"
        |> __MODULE__.query()
        |> parse_measurements_list!()
      end

      def list_measurements() do
        "SHOW MEASUREMENTS"
        |> __MODULE__.query()
        |> parse_measurements_list()
      end

      def drop_measurement(measurement_name) do
        "DROP MEASUREMENT #{measurement_name}"
        |> __MODULE__.execute()
      end

      def create_db() do
        Sanbase.Utils.Config.get(:database)
        |> Instream.Admin.Database.create()
        |> __MODULE__.execute()
      end

      # Private functions

      defp parse_measurements_list!(%{results: [%{error: error}]}), do: raise(error)

      defp parse_measurements_list!(%{
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
        measurements
        |> Enum.map(&Kernel.hd/1)
      end

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
    end
  end
end