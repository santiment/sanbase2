defmodule SanbaseWeb.GenericAdmin.SourceSlugMapping do
  @behaviour SanbaseWeb.GenericAdmin
  def schema_module, do: Sanbase.Project.SourceSlugMapping
  def resource_name, do: "source_slug_mappings"
  def singular_resource_name, do: "source_slug_mapping"

  import Ecto.Query

  def resource() do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:project, :non_crypto_asset],
      new_fields: [:project, :non_crypto_asset, :source, :slug],
      edit_fields: [:project, :non_crypto_asset, :source, :slug],
      fields_override: %{
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        },
        source: %{
          collection: ["cryptocompare", "coinmarketcap", "binance", "hyperliquid"],
          type: :select
        }
      },
      belongs_to_fields: %{
        project: SanbaseWeb.GenericAdmin.belongs_to_project(),
        non_crypto_asset: %{
          query: from(a in Sanbase.NonCryptoAsset, order_by: a.name),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "non_crypto_assets",
          search_fields: [:name, :slug, :ticker]
        }
      }
    }
  end
end
