defmodule SanbaseWeb.Graphql.Schema.EmailQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.EmailResolver

  object :email_mutations do
    field :verify_email_newsletter, :boolean do
      arg(:email, non_null(:string))

      resolve(&EmailResolver.verify_email_newsletter/3)
    end

    field :subscribe_email_newsletter, :boolean do
      arg(:email, non_null(:string))
      arg(:token, non_null(:string))
      arg(:type, :string, default_value: "weekly_digest")

      resolve(&EmailResolver.subscribe_email_newsletter/3)
    end
  end
end
