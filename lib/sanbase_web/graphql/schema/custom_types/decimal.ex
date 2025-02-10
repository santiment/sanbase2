defmodule SanbaseWeb.Graphql.CustomTypes.Decimal do
  @moduledoc false
  use Absinthe.Schema.Notation

  if Code.ensure_loaded?(Decimal) do
    scalar :decimal do
      description("""
      The `Decimal` scalar type represents signed double-precision fractional
      values parsed by the `Decimal` library.  The Decimal appears in a JSON
      response as a string to preserve precision.
      """)

      serialize(&Absinthe.Type.Custom.Decimal.serialize/1)
      parse(&Absinthe.Type.Custom.Decimal.parse/1)
    end
  end
end
