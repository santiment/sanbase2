defmodule SanbaseWeb.Graphql.SignalsHistoricalActivityTypes do
  use Absinthe.Schema.Notation

  object :signal_historical_activity_paginated do
    field(:activity, list_of(:signal_historical_activity))
    field(:cursor, :cursor)
  end

  object :signal_historical_activity do
    field(:user_trigger, non_null(:user_trigger))
    field(:triggered_at, non_null(:naive_datetime))
    field(:payload, non_null(:json))
  end
end
