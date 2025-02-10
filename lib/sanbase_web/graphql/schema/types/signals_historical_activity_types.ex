defmodule SanbaseWeb.Graphql.AlertsHistoricalActivityTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :alert_historical_activity_paginated do
    field(:activity, list_of(:alert_historical_activity))
    field(:cursor, :cursor)
  end

  object :alert_historical_activity do
    field(:trigger, non_null(:trigger))
    field(:triggered_at, non_null(:datetime))
    field(:payload, :json)
    field(:data, :json)
  end
end
