defmodule Sanbase.ExAdmin.Auth.User do
  use ExAdmin.Register

  import Ecto.Query, warn: false
  alias Sanbase.Auth.EthAccount

  register_resource Sanbase.Auth.User do
    show user do
      attributes_table

      panel "Eth accounts" do
        table_for user.eth_accounts do
          column(:id, link: true)
          column(:address)

          unless Mix.env() == :dev do
            column("San balance", fn eth_account ->
              EthAccount.san_balance(eth_account)
            end)
          end
        end
      end
    end

    form user do
      inputs do
        input(user, :test_san_balance)
      end
    end
  end
end
