defmodule SanbaseWeb.GenericAdmin.Ico do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query
  def schema_module, do: Sanbase.Model.Ico
  def resource_name, do: "icos"
  def singular_resource_name, do: "ico"

  def resource() do
    %{
      actions: [:new, :edit],
      preloads: [:cap_currency, :project],
      new_fields: [
        :project,
        :start_date,
        :end_date,
        :token_usd_ico_price,
        :token_eth_ico_price,
        :token_btc_ico_price,
        :tokens_issued_at_ico,
        :tokens_sold_at_ico,
        :minimal_cap_amount,
        :maximal_cap_amount,
        :contract_block_number,
        :contract_abi,
        :cap_currency,
        :comments
      ],
      edit_fields: [
        :project,
        :start_date,
        :end_date,
        :token_usd_ico_price,
        :token_eth_ico_price,
        :token_btc_ico_price,
        :tokens_issued_at_ico,
        :tokens_sold_at_ico,
        :minimal_cap_amount,
        :maximal_cap_amount,
        :contract_block_number,
        :contract_abi,
        :cap_currency,
        :comments
      ],
      belongs_to_fields: %{
        project: SanbaseWeb.GenericAdmin.belongs_to_project(),
        cap_currency: %{
          query: from(c in Sanbase.Model.Currency, order_by: c.code),
          transform: fn rows -> Enum.map(rows, &{&1.code, &1.id}) end,
          resource: "currencies",
          search_fields: [:code]
        }
      },
      fields_override: %{
        comments: %{
          type: :text
        },
        contract_abi: %{
          type: :text
        },
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        }
      }
    }
  end
end
