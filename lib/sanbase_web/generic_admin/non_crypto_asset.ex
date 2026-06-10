defmodule SanbaseWeb.GenericAdmin.NonCryptoAsset do
  @behaviour SanbaseWeb.GenericAdmin

  def schema_module(), do: Sanbase.NonCryptoAsset
  def resource_name(), do: "non_crypto_assets"
  def singular_resource_name(), do: "non_crypto_asset"

  @fields [
    :slug,
    :name,
    :ticker,
    :asset_type,
    :description,
    :logo_url,
    :website_link,
    :is_hidden,
    :hidden_reason
  ]

  def resource() do
    %{
      actions: [:new, :edit],
      index_fields: [:id, :slug, :name, :ticker, :asset_type, :is_hidden],
      new_fields: @fields,
      edit_fields: @fields,
      fields_override: %{
        asset_type: %{
          collection: Sanbase.NonCryptoAsset.asset_types() |> Enum.map(&to_string/1),
          type: :select
        },
        description: %{type: :text}
      }
    }
  end
end
