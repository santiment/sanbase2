defmodule SanbaseWeb.Graphql.MonitoredTwitterHandleTypes do
  use Absinthe.Schema.Notation

  object :monitored_twitter_handle do
    field(:handle, non_null(:string))
    field(:notes, :string)

    field(:inserted_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
  end
end
