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
        non_crypto_asset_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.NonCryptoAsset.non_crypto_asset_link/1
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

  # The changeset blocks a confirmed-invalid hyperliquid coin outright (shown as
  # a form error). When HL could not be reached to verify in time it lets the
  # write through and marks the changeset; surface that as a warning here so the
  # admin knows the mapping was saved without verification.
  def after_filter(_record, %Ecto.Changeset{} = changeset, _changes) do
    case Ecto.Changeset.get_change(changeset, :coin_verification) do
      "unverified" ->
        {:error,
         "saved, but the coin could not be verified against the Hyperliquid universe (timed out). Double-check the slug."}

      _ ->
        :ok
    end
  end
end
