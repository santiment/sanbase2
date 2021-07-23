defmodule Sanbase.Repo.Migrations.InsertExchangeEthAddresses do
  use Ecto.Migration

  alias Sanbase.Repo
  alias Sanbase.Model.ExchangeEthAddress

  def up do
    address_data
    |> Enum.map(&update_or_create_eth_address/1)
    |> Enum.each(&Repo.insert_or_update!/1)
  end

  defp update_or_create_eth_address({name, address, comments}) do
    Repo.get_by(ExchangeEthAddress, address: address)
    |> case do
      nil ->
        %ExchangeEthAddress{}
        |> ExchangeEthAddress.changeset(%{address: address, name: name, comments: comments})

      exch_address ->
        exch_address
        |> ExchangeEthAddress.changeset(%{name: name, comments: comments})
    end
  end

  def down do
  end

  defp address_data do
    [
      {"Binance contract owner wallet", "0x00c5e04176d95a286fcce0e68c683ca0bfec8454",
       "This is the owner of the BNB contract and is the #1 owner of BNB."},
      {"Binance hot wallet", "0x3f5ce5fbfe3e9af3971dd833d26ba9b5c936f0be", nil},
      {"Binance related wallet", "0xfe9e8709d3215310075d67e3ed32a380ccf451c8",
       "2nd largest BNB address. Yet to confirm relationship but it holds around 6 Billion dollars worth of tokens and most tokens are Binance related. Transfers to Binance rather often. Could be unidentified binance wallet #2. Or maybe...."},
      {"Bitfinex cold wallet (?)", "0xf4B51B14b9EE30dc37EC970B50a486F37686E2a8", nil},
      {"Bitfinex", "0x7180EB39A6264938FDB3EfFD7341C4727c382153", nil},
      {"Bitfinex wallet1", "0x1151314c646ce4e0efd76d1af4760ae66a9fe30f", "Verified by etherscan"},
      {"Bitfinex wallet2", "0x7727e5113d1d161373623e5f49fd568b4f543a9e", "Verified by etherscan"},
      {"Bitfinex wallet3", "0x4fdd5eb2fb260149a3903859043e962ab89d8ed4", "Verified by etherscan"},
      {"Bitfinex wallet4", "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa", "Verified by etherscan"},
      {"Bitfinex old wallet", "0xcafb10ee663f465f9d10588ac44ed20ed608c11e",
       "Verified by etherscan"},
      {"Bittrex", "0xfbb1b73c4f0bda4f67dca266ce6ef42f520fbb98", nil},
      {"Bittrex_2", "0xE94b04a0FeD112f3664e45adb2B8915693dD5FF3", nil},
      {"coinexchange.io", "0x4b01721f0244e7c5b5f63c20942850e447f5a5ee", nil},
      {"etherdelta_2", "0x8d12a197cb00d4747a1fe03395095ce2a5cc6819", nil},
      {"IDEX_1", "0x2a0c0dbecc7e4d658f48e01e3fa353f44050c208", nil},
      {"Kraken_1", "0x2910543af39aba0cd09dbb2d50200b3e800a63d2", nil},
      {"Kraken_2", "0x0a869d79a7052c7f1b55a8ebabbea3420f0d1e13", nil},
      {"Kraken_3", "0xe853c56864a2ebe4576a807d26fdc4a0ada51919", nil},
      {"Kraken_4", "0x267be1c1d684f78cb4f6a176c4911b741e4ffdc0", nil},
      {"KrakenREP", "0xA2a8f158aed54CE9A73d41EEEc23Bf3a51b5654D", nil},
      {"liqui.io", "0x8271b2e8cbe29396e9563229030c89679b9470db", nil},
      {"liqui.io_2", "0x5E575279bf9f4acf0A130c186861454247394C06", nil},
      {"Poloniex coldwallet", "0xb794f5ea0ba39494ce839613fffba74279579268",
       "Verified by etherscan"},
      {"Poloniex wallet1", "0x32be343b94f860124dc4fee278fdcbd38c102d88", "Verified by etherscan"},
      {"Poloniex's $REP wallet address", "0xab11204cfeaccffa63c2d23aef2ea9accdb0a0d5", nil},
      {"Poloniex-GNT", "0x0536806df512D6cDDE913Cf95c9886f65b1D3462", nil},
      {"Poloniex's $ZRX wallet", "0xead6be34ce315940264519f250d8160f369fa5cd", nil},
      {"Poloniex's contract address that transfers all incoming funds to Polo wallet1",
       "0x209c4784ab1e8183cf58ca33cb740efbf3fc18ef", nil},
      {"Poloniex's Gnosis (GNO) wallet", "0x48d466b7c0d32b61e8a82cd2bcf060f7c3f966df", nil},
      {"Shapeshift", "0x70faa28a6b8d6829a4b1e649d26ec9a2a39ba413", nil},
      {"Yobit", "0xf5bec430576ff1b82e44ddb5a1c93f6f9d0884f3", nil},
      {"yunbi_1", "0xd94c9ff168dc6aebf9b6cc86deff54f3fb0afc33", nil}
    ]
  end
end
