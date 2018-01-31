defmodule SanbaseWeb.Graphql.Middlewares.MultipleAuthTest do
  use ExUnit.Case

  alias SanbaseWeb.Graphql.Middlewares.MultipleAuth

  defmodule TestResolvingAuth do
    def call(resolution, _),
      do: Absinthe.Resolution.put_result(resolution, {:error, :you_shall_not_pass})
  end

  defmodule TestNotResolvingAuth do
    def call(resolution, _), do: resolution
  end

  test "when no auth methods are specified, access should be denied" do
    result = MultipleAuth.call(%Absinthe.Resolution{}, [])

    assert result.state == :resolved
    assert result.errors == [:unauthorized]
  end

  test "when all auth methods resolves, access denied should be returned" do
    result = MultipleAuth.call(%Absinthe.Resolution{}, [TestResolvingAuth])

    assert result.state == :resolved
    assert result.errors == [:unauthorized]
  end

  test "when an auth methods do not resolve, that resolution should be returned" do
    result = MultipleAuth.call(%Absinthe.Resolution{}, [TestResolvingAuth, TestNotResolvingAuth])

    assert result.state == :unresolved
    assert result.errors == []
  end
end
