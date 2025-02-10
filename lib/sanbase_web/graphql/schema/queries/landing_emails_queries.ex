defmodule SanbaseWeb.Graphql.Schema.LandingEmailsQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.LandingEmailsResolver

  object :landing_emails_mutations do
    @desc """
    Add emails from sanr.network landing page
    """
    field :add_sanr_email, :boolean do
      arg(:email, non_null(:string))

      resolve(&LandingEmailsResolver.add_sanr_email/3)
    end

    @desc """
    Add emails from alpha naratives landing page
    """
    field :add_alpha_naratives_email, :boolean do
      arg(:email, non_null(:string))

      resolve(&LandingEmailsResolver.add_alpha_naratives_email/3)
    end
  end
end
