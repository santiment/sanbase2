defmodule SanbaseWeb.Graphql.PaginationTypes do
  use Absinthe.Schema.Notation

  enum(:cursor_type, values: [:before, :after])

  input_object :cursor_input_no_order do
    field(:type, non_null(:cursor_type))
    field(:datetime, non_null(:datetime))
  end

  input_object :cursor_input do
    field(:type, non_null(:cursor_type))
    field(:datetime, non_null(:datetime))
    field(:order, :direction_type, default_value: :asc)
  end

  object :cursor do
    field(:before, :datetime)
    field(:after, :datetime)
  end
end
