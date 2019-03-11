defmodule SanbaseWeb.Graphql.PaginationTypes do
  use Absinthe.Schema.Notation

  enum(:cursor_type, values: [:before, :after])

  input_object :cursor_input do
    field(:type, non_null(:cursor_type))
    field(:datetime, non_null(:naive_datetime))
  end

  object :cursor do
    field(:before, :naive_datetime)
    field(:after, :naive_datetime)
  end
end
