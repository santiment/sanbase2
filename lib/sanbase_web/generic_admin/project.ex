defmodule SanbaseWeb.GenericAdmin.Project do
  def schema_module, do: Sanbase.Project

  def resource() do
    %{
      preloads: [:infrastructure],
      index_fields: [
        :id,
        :ticker,
        :name,
        :slug,
        :website_link,
        :infrastructure_id,
        :token_decimals,
        :is_hidden
      ],
      edit_fields: [:ticker, :name, :slug],
      funcs: %{
        infrastructure_id: &__MODULE__.link/1
      }
    }
  end

  def link(row) do
    if row.infrastructure do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "infrastructures",
        row.infrastructure.id,
        row.infrastructure.code
      )
    end
  end
end
