defmodule SanbaseWeb.ExAdmin.Accounts.UniswapStaking do
  use ExAdmin.Register

  register_resource Sanbase.Auth.User.UniswapStaking do
    show uniswap_staking do
      attributes_table(all: true)
    end
  end
end
