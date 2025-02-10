defmodule SanbaseWeb.Graphql.Middlewares.MultipleAuth do
  @moduledoc """
  Authentication middleware, which allows to specify multiple auth methods. If
  one of them works, the request will continue to the resolver. Otherwise the
  response will be terminated and an unauthorized error will be returned.
  """
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution

  def call(resolution, auths) do
    auths
    |> Enum.map(fn
      {middleware, config} -> middleware.call(resolution, config)
      middleware -> middleware.call(resolution, [])
    end)
    |> Enum.find(&(&1.state == :unresolved))
    |> case do
      nil ->
        Resolution.put_result(resolution, {:error, :unauthorized})

      resolution ->
        resolution
    end
  end
end
