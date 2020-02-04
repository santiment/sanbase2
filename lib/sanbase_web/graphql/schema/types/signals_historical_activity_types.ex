defmodule SanbaseWeb.Graphql.SignalsHistoricalActivityTypes do
  use Absinthe.Schema.Notation

  object :signal_historical_activity_paginated do
    field(:activity, list_of(:signal_historical_activity))
    field(:cursor, :cursor)
  end

  object :signal_historical_activity do
    field(:trigger, non_null(:trigger))
    field(:triggered_at, non_null(:datetime))
    field(:payload, :json)
    field(:data, :json)
  end
end
