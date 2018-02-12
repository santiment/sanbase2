# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Sanbase.Repo.insert!(%Sanbase.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Sanbase.Model.Project
alias Sanbase.Model.ProjectEthAddress
alias Sanbase.Model.ProjectBtcAddress
alias Sanbase.Model.Infrastructure
alias Sanbase.Repo
alias Sanbase.Auth.{User, EthAccount}

infrastructure_eth = Infrastructure.get_or_insert("ETH")

make_project = fn {name, ticker, logo_url, coinmarkecap_id, infrastructure_code} ->
  infrastructure =
    case infrastructure_code do
      "ETH" -> infrastructure_eth
      nil -> infrastructure_eth
      _ -> Infrastructure.get_or_insert(infrastructure_code)
    end

  %Project{
    name: name,
    ticker: ticker,
    logo_url: logo_url,
    coinmarketcap_id: coinmarkecap_id,
    infrastructure: infrastructure
  }
end

make_btc_address = fn {name, address} ->
  [
    %ProjectBtcAddress{
      project: Repo.get_by(Project, name: name),
      address: address
    }
  ]
end

make_eth_address = fn {name, address} ->
  [
    %ProjectEthAddress{
      project: Repo.get_by(Project, name: name),
      address: address
    }
  ]
end

########################################
# Old Sanbase projects
########################################
[
  {"EOS", "EOS", "eos.png", "eos", "ETH"},
  {"Golem", "GNT", "golem.png", "golem-network-tokens", "ETH"},
  {"Iconomi", "ICN", "iconomi.png", "iconomi", "ETH"},
  {"Gnosis", "GNO", "gnosis.png", "gnosis-gno", "ETH"},
  {"Status", "SNT", "status.png", "status", "ETH"},
  {"TenX", "PAY", "tenx.png", "tenx", "ETH"},
  {"Basic Attention Token", "BAT", "basic-attention-token.png", "basic-attention-token", "ETH"},
  {"Populous", "PPT", "populous.png", "populous", "ETH"},
  {"DigixDAO", "DGD", "digixdao.png", "digixdao", "ETH"},
  {"Bancor", "BNT", "bancor.png", "bancor", "ETH"},
  {"MobileGo", "MGO", "mobilego.png", "mobilego", "ETH"},
  {"Aeternity", "AE", "aeternity.png", "aeternity", "ETH"},
  {"SingularDTV", "SNGLS", "singulardtv.png", "singulardtv", "ETH"},
  {"Civic", "CVC", "civic.png", "civic", "ETH"},
  {"Aragon", "ANT", "aragon.png", "aragon", "ETH"},
  {"FirstBlood", "1ST", "firstblood.png", "firstblood", "ETH"},
  {"Etheroll", "DICE", "etheroll.png", "etheroll", "ETH"},
  {"Melon", "MLN", "melon.png", "melon", "ETH"},
  {"iExec RLC", "RLC", "rlc.png", "rlc", "ETH"},
  {"Stox", "STX", "stox.png", "stox", "ETH"},
  {"Humaniq", "HMQ", "humaniq.png", "humaniq", "ETH"},
  {"Polybius", "PLBT", "polybius.png", "polybius", "ETH"},
  {"Santiment", "SAN", "santiment.png", "santiment", "ETH"},
  {"district0x", "DNT", "district0x.png", "district0x", "ETH"},
  {"DAO.Casino", "BET", "dao-casino.png", "dao-casino", "ETH"},
  {"Centra", "CTR", "centra.png", "centra", "ETH"},
  {"Tierion", "TNT", "tierion.png", "tierion", "ETH"},
  {"Matchpool", "GUP", "guppy.png", "guppy", "ETH"},
  {"Nebulas", "NAS", "nebulas.png", "nebulas-token", "ETH"}
]
|> Enum.map(make_project)
|> Enum.each(&Repo.insert!/1)

[
  {"EOS", "0x10F0c9112b255507701df1b1be5D8dcd9A82bb5e"},
  {"Golem", "0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9"},
  {"Iconomi", "0x154Af3E01eC56Bc55fD585622E33E3dfb8a248d8"},
  {"Gnosis", "0x851b7F3Ab81bd8dF354F0D7640EFcD7288553419"},
  {"Status", "0xA646E29877d52B9e2De457ECa09C724fF16D0a2B"},
  {"TenX", "0x185f19B43d818E10a31BE68f445ef8EDCB8AFB83"},
  {"Basic Attention Token", "0x44fcfaBfBe32024a01b778c025D70498382CCEd0"},
  {"Populous", "0xca48BA80Cfa6CC06963B62AeE48000f031c7E2dC"},
  {"DigixDAO", "0xf0160428a8552ac9bb7e050d90eeade4ddd52843"},
  {"Bancor", "0x5894110995B8c8401Bd38262bA0c8EE41d4E4658"},
  {"MobileGo", "0x6d7ea347ef837462a55337C4f772868F2A80B863"},
  {"Aeternity", "0x15c19E6c203E2c34D1EDFb26626bfc4F65eF96F0"},
  {"SingularDTV", "0x5901Deb2C898D5dBE5923E05e510E95968a35067"},
  {"Civic", "0x2323763D78bF7104b54A462A79C2Ce858d118F2F"},
  {"Aragon", "0xcafE1A77e84698c83CA8931F54A755176eF75f2C"},
  {"FirstBlood", "0xa5384627F6DcD3440298E2D8b0Da9d5F0FCBCeF7"},
  {"Etheroll", "0x24C3235558572cff8054b5a419251D3B0D43E91b"},
  {"Melon", "0x8615F13C12c24DFdca0ba32511E2861BE02b93b2"},
  {"iExec RLC", "0x21346283a31A5AD10Fa64377E77A8900Ac12d469"},
  {"Stox", "0x3dD88B391fe62a91436181eD2D43E20B86CDE60c"},
  {"Humaniq", "0xa2c9a7578e2172f32a36c5c0e49d64776f9e7883"},
  {"Polybius", "0xe9Eca8bB5e61e8e32f26B5E8c117561F68084a9C"},
  {"Santiment", "0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a"},
  {"district0x", "0xd20E4d854C71dE2428E1268167753e4C7070aE68"},
  {"DAO.Casino", "0x1446bf7AF9dF857b23a725646D94f9Ec49802227"},
  {"Centra", "0x96A65609a7B84E8842732DEB08f56C3E21aC6f8a"},
  {"Tierion", "0x0C4b367e876d18d5c102023D9240DD7e9C11b380"},
  {"Matchpool", "0x1c10aD0b5f1b4013173f05B4cc05a60cBBAa6536"},
  {"Nebulas", "0x5d65D971895Edc438f465c17DB6992698a52318D"}
]
|> Enum.flat_map(make_eth_address)
|> Enum.each(&Repo.insert!/1)

#######################################
# Projecttransparency projects
#######################################

[
  {"CFI", "Cofound.it", "cofound-it.png", "cofound-it", "ETH"},
  {"Dappbase", "DAP", nil, nil, "ETH"},
  {"Encrypgen", "DNA", nil, "encrypgen", "ETH"},
  {"Etherisc", "RSC", nil, nil, "ETH"},
  {"Expanse/Tokenlab", "EXP/LAB", "expanse.png", "expanse", "ETH"},
  {"Gatcoin.ioCFI", "GAT", nil, nil, "ETH"},
  {"Hshare", "HSR", "hshare.png", "hshare", "ETH"},
  {"Indorse", "IND", "indorse-token.png", "indorse-token", "ETH"},
  {"Lykke", "LKK", "lykke.png", "lykke", "ETH"},
  {"Maecenas", "ART", "maecenas.png", "maecenas", "ETH"},
  {"Musiconomi", "MCI", "musiconomi.png", "musiconomi", "ETH"},
  {"Virgil Capital", "VIC", nil, nil, "ETH"}
]
|> Enum.map(make_project)
|> Enum.each(&Repo.insert!/1)

[
  {"Encrypgen", "0x683a0aafa039406c104d814b9f244eea721445a7"},
  {"Etherisc", "0x35792029777427920ce7aDecccE9e645465e9C72"},
  {"Expanse/Tokenlab", "0xd1ea8853619aaad66f3f6c14ca22430ce6954476"},
  {"Expanse/Tokenlab", "0xf83fd4b62ccb4b5c4213278b6b506eb2f19988d0"},
  {"Indorse", "0x1c82ee5b828455F870eb2998f2c9b6Cc2d52a5F6"},
  {"Indorse", "0x26967201d4d1e1aa97554838defa4fc4d010ff6f"},
  {"Maecenas", "0x02DC3b8AB87c562CdCE707647bd1ba21C390Faf4"},
  {"Maecenas", "0x9B60874D7bc4e4fBDd142e0F5a12002e4F7715a6"},
  {"Musiconomi", "0xc7CD9d874F93F2409F39A95987b3E3C738313925"}
]
|> Enum.flat_map(make_eth_address)
|> Enum.each(&Repo.insert!/1)

[
  {"Encrypgen", "13MoQt2n9cHNzbpt8PfeVYp2cehgzRgj6v"},
  {"Encrypgen", "16bv1XAqh1YadAWHgDWgxKuhhns7T2EywG"}
]
|> Enum.flat_map(make_btc_address)
|> Enum.each(&Repo.insert!/1)

user =
  %User{
    email: "john.d@santiment.net",
    username: "John Dow",
    salt: "LgcwR3e98PR/gvgV7Ph1+ZXnw4yhTz25k08QLi/39qdCt/V0XOGlJRiL938NtJk0"
  }
  |> Repo.insert!()

%EthAccount{address: "0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a", user_id: user.id}
|> Repo.insert!()

### Import random Github activity for SAN ticker

alias Sanbase.Influxdb.Measurement
alias Sanbase.Github

defmodule SeedsGithubActivityImporter do
  def previous_hour(datetime) do
    datetime
    |> DateTime.to_unix()
    |> Kernel.-(3600)
    |> DateTime.from_unix!()
  end

  def import_gh_activity(datetime, _activity, _ticker, 0), do: :ok

  def import_gh_activity(datetime, activity, ticker, n) do
    Github.Store.import(%Measurement{
      timestamp: datetime |> DateTime.to_unix(:nanoseconds),
      fields: %{activity: activity},
      name: ticker
    })

    datetime = previous_hour(datetime)
    activity = :rand.uniform(100)
    import_gh_activity(datetime, activity, ticker, n - 1)
  end
end

Github.Store.create_db()
Github.Store.drop_measurement("SAN")

SeedsGithubActivityImporter.import_gh_activity(DateTime.utc_now(), 50, "SAN", 500)

#########
# Exchange addresses
#########
defmodule InsertExchangeEthAddresses do
  alias Sanbase.Model.ExchangeEthAddress

  def run do
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

InsertExchangeEthAddresses.run()
