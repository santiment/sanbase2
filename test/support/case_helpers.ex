defmodule Sanbase.CaseHelpers do
  defmacro checkout_shared(tags) do
    quote bind_quoted: [tags: tags] do
      repos =
        if tags[:checkout_repo] do
          tags[:checkout_repo]
        else
          Sanbase.Repo
        end

      # Allow defining of multiple repos
      repos
      |> List.wrap()
      |> Enum.each(fn repo ->
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)

        unless tags[:async] do
          Ecto.Adapters.SQL.Sandbox.mode(repo, {:shared, self()})
        end
      end)
    end
  end
end
