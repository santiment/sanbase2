defmodule SanbaseWeb.Graphql.WidgetTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :active_widget do
    field(:title, non_null(:string))
    field(:description, :string)
    field(:video_link, :string)
    field(:image_link, :string)

    field :created_at, non_null(:datetime) do
      resolve(fn %{inserted_at: inserted_at}, _, _ ->
        {:ok, inserted_at}
      end)
    end

    field(:updated_at, non_null(:datetime))
  end
end
