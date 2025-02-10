defmodule SanbaseWeb.Graphql.FreeFormJsonStorageTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :free_form_json_storage do
    field(:key, non_null(:string))
    field(:value, non_null(:json))
    field(:inserted_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
  end
end
