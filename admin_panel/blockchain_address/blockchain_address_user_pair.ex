defmodule SanbaseWeb.ExAdmin.BlockchainAddressUserPair do
  use ExAdmin.Register

  register_resource Sanbase.BlockchainAddress.BlockchainAddressUserPair do
    show pair do
      attributes_table do
        row(:id)
        row(:notes)
        row(:user, link: true)
        row(:blockchain_address, link: true)
      end

      panel "Labels" do
        markup_contents do
          a ".btn .btn-primary",
            href:
              "/admin/blockchain_address_user_pair_labels/new?blockchain_address_user_pair_id=" <>
                to_string(pair.id) do
            "New Label"
          end
        end

        table_for Sanbase.Repo.preload(pair, [:labels]).labels do
          column(:name)
          column(:notes)
        end
      end
    end
  end
end
