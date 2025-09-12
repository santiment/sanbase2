defmodule SanbaseWeb.Graphql.Middlewares.AfterCacheTransform do
  @behaviour Absinthe.Middleware
  alias Absinthe.Resolution

  def call(%Resolution{errors: [_ | _]} = resolution, _opts), do: resolution

  def call(%Resolution{value: value} = resolution, _opts) when not is_nil(value) do
    args = resolution.arguments

    with {:ok, result} <- SanbaseWeb.Graphql.Helpers.Utils.fit_from_datetime(value, args) do
      %{
        resolution
        | value: result
      }
    else
      _ -> resolution
    end
  end

  def call(resolution, _opts), do: resolution
end
