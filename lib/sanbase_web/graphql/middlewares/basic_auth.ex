defmodule SanbaseWeb.Graphql.Middlewares.BasicAuth do
  @behavior Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{context: %{auth: %{auth_method: :basic}}} = resolution, _) do
    resolution
  end

  def call(resolution, _) do
    resolution
    |> Resolution.put_result({:error, :unauthorized})
  end
end
