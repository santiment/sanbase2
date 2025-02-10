defmodule SanbaseWeb.Graphql.WebinarTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :webinar do
    field(:url, :string)
    field(:title, non_null(:string))
    field(:description, non_null(:string))
    field(:is_pro, non_null(:boolean))
    field(:image_url, non_null(:string))
    field(:start_time, non_null(:datetime))
    field(:end_time, non_null(:datetime))
    field(:inserted_at, non_null(:datetime))
  end
end
