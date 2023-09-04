defmodule SanbaseWeb.Graphql.Resolvers.SanrResolver do
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1]

  def add_sanr_email(_root, %{email: email}, _resolution) do
    case Sanbase.Sanr.Email.create(email) do
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
