defmodule Sanbase.Prices.Store do
  @moduledoc false

  # Define the module so the importers continue to work.
  # No data will be fetched via this module, but the prices need to be imported
  # in influxdb so other modules work
  use Sanbase.Influxdb.Store
end
