defmodule SanbaseWeb.Graphql.Resolvers.LandingEmailsResolver do
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]

  def add_sanr_email(_root, %{email: email}, _resolution) do
    case Sanbase.LandingEmails.SanrEmail.create(email) do
      {:ok, _} ->
        {:ok, true}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot add email", details: changeset_errors(changeset)
        }
    end
  end

  def add_alpha_naratives_email(_root, %{email: email}, _resolution) do
    case Sanbase.LandingEmails.AlphaNaratives.create(email) do
      {:ok, _} ->
        {:ok, true}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot add email", details: changeset_errors(changeset)
        }
    end
  end
end
