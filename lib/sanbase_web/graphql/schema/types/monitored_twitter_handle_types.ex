defmodule SanbaseWeb.Graphql.MonitoredTwitterHandleTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :monitored_twitter_handle do
    field(:handle, non_null(:string))
    field(:notes, :string)
    field(:status, :string)

    @desc ~s"""
    Comment submitted by a moderator when approving or declining a handle.
    """
    field(:comment, :string)

    field(:inserted_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
  end
end
