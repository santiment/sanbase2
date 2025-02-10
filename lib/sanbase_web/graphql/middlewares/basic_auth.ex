defmodule SanbaseWeb.Graphql.Middlewares.BasicAuth do
  @moduledoc false
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(%Resolution{context: %{auth: %{auth_method: :basic}}} = resolution, _) do
    resolution
  end

  def call(resolution, _) do
    Resolution.put_result(resolution, {:error, :unauthorized})
  end
end
