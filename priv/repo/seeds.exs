# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Sanbase.Repo.insert(%Sanbase.SomeSchema{})
#

alias Sanbase.Model.Project
alias Sanbase.Model.ProjectEthAddress
alias Sanbase.Model.ProjectBtcAddress
alias Sanbase.Model.Infrastructure
alias Sanbase.Repo
alias Sanbase.Auth.{User, EthAccount}

infrastructure_eth = Infrastructure.get_or_insert("ETH")

insert_on_conflict_nothing = fn item ->
  Repo.insert(item, on_conflict: :nothing)
end

make_project = fn {name, ticker, logo_url, coinmarkecap_id, infrastructure_code, contract,
                   token_decimals} ->
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
    infrastructure: infrastructure,
    main_contract_address: contract,
    token_decimals: token_decimals
  }
end

make_btc_address = fn {name, address} ->
  project = Repo.get_by(Project, name: name)

  [
    %ProjectBtcAddress{}
    |> ProjectBtcAddress.changeset(%{
      address: address,
      project_id: project.id
    })
  ]
end

make_eth_address = fn {name, address} ->
  project = Repo.get_by(Project, name: name)

  [
    %ProjectEthAddress{}
    |> ProjectEthAddress.changeset(%{
      address: address,
      project_id: project.id
    })
  ]
end

########################################
# Old Sanbase projects
########################################
[
  {"EOS", "EOS", "eos.png", "eos", "ETH", nil, 18},
  {"Golem", "GNT", "golem.png", "golem-network-tokens", "ETH", nil, 18},
  {"Iconomi", "ICN", "iconomi.png", "iconomi", "ETH", nil, 18},
  {"Gnosis", "GNO", "gnosis.png", "gnosis-gno", "ETH", nil, 18},
  {"Status", "SNT", "status.png", "status", "ETH", nil, 18},
  {"TenX", "PAY", "tenx.png", "tenx", "ETH", nil, 18},
  {"Basic Attention Token", "BAT", "basic-attention-token.png", "basic-attention-token", "ETH",
   nil, 18},
  {"Populous", "PPT", "populous.png", "populous", "ETH", nil, 18},
  {"DigixDAO", "DGD", "digixdao.png", "digixdao", "ETH", nil, 18},
  {"Bancor", "BNT", "bancor.png", "bancor", "ETH", nil, 18},
  {"MobileGo", "MGO", "mobilego.png", "mobilego", "ETH", nil, 18},
  {"Aeternity", "AE", "aeternity.png", "aeternity", "ETH", nil, 18},
  {"SingularDTV", "SNGLS", "singulardtv.png", "singulardtv", "ETH", nil, 18},
  {"Civic", "CVC", "civic.png", "civic", "ETH", nil, 18},
  {"Aragon", "ANT", "aragon.png", "aragon", "ETH", nil, 18},
  {"FirstBlood", "1ST", "firstblood.png", "firstblood", "ETH", nil, 18},
  {"Etheroll", "DICE", "etheroll.png", "etheroll", "ETH", nil, 18},
  {"Melon", "MLN", "melon.png", "melon", "ETH", nil, 18},
  {"iExec RLC", "RLC", "rlc.png", "rlc", "ETH", nil, 18},
  {"Stox", "STX", "stox.png", "stox", "ETH", nil, 18},
  {"Humaniq", "HMQ", "humaniq.png", "humaniq", "ETH", nil, 18},
  {"Polybius", "PLBT", "polybius.png", "polybius", "ETH", nil, 18},
  {"Santiment", "SAN", "santiment.png", "santiment", "ETH",
   "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098", 18},
  {"district0x", "DNT", "district0x.png", "district0x", "ETH", nil, 18},
  {"DAO.Casino", "BET", "dao-casino.png", "dao-casino", "ETH", nil, 18},
  {"Centra", "CTR", "centra.png", "centra", "ETH", nil, 18},
  {"Tierion", "TNT", "tierion.png", "tierion", "ETH", nil, 18},
  {"Matchpool", "GUP", "guppy.png", "guppy", "ETH", nil, 18},
  {"Nebulas", "NAS", "nebulas.png", "nebulas-token", "ETH", nil, 18},
  {"Ethereum", "ETH", "ethereum.png", "ethereum", "ETH", nil, 18}
]
|> Enum.map(make_project)
|> Enum.each(insert_on_conflict_nothing)

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
|> Enum.each(insert_on_conflict_nothing)

#######################################
# Projecttransparency projects
#######################################

[
  {"CFI", "Cofound.it", "cofound-it.png", "cofound-it", "ETH", nil, 18},
  {"Encrypgen", "DNA", nil, "encrypgen", "ETH", nil, 18},
  {"Expanse/Tokenlab", "EXP/LAB", "expanse.png", "expanse", "ETH", nil, 18},
  {"Hshare", "HSR", "hshare.png", "hshare", "ETH", nil, 18},
  {"Indorse", "IND", "indorse-token.png", "indorse-token", "ETH", nil, 18},
  {"Lykke", "LKK", "lykke.png", "lykke", "ETH", nil, 18},
  {"Maecenas", "ART", "maecenas.png", "maecenas", "ETH", nil, 18},
  {"Musiconomi", "MCI", "musiconomi.png", "musiconomi", "ETH", nil, 18}
]
|> Enum.map(make_project)
|> Enum.each(insert_on_conflict_nothing)

[
  {"Encrypgen", "0x683a0aafa039406c104d814b9f244eea721445a7"},
  {"Expanse/Tokenlab", "0xd1ea8853619aaad66f3f6c14ca22430ce6954476"},
  {"Expanse/Tokenlab", "0xf83fd4b62ccb4b5c4213278b6b506eb2f19988d0"},
  {"Indorse", "0x1c82ee5b828455F870eb2998f2c9b6Cc2d52a5F6"},
  {"Indorse", "0x26967201d4d1e1aa97554838defa4fc4d010ff6f"},
  {"Maecenas", "0x02DC3b8AB87c562CdCE707647bd1ba21C390Faf4"},
  {"Maecenas", "0x9B60874D7bc4e4fBDd142e0F5a12002e4F7715a6"},
  {"Musiconomi", "0xc7CD9d874F93F2409F39A95987b3E3C738313925"}
]
|> Enum.flat_map(make_eth_address)
|> Enum.each(insert_on_conflict_nothing)

[
  {"Encrypgen", "13MoQt2n9cHNzbpt8PfeVYp2cehgzRgj6v"},
  {"Encrypgen", "16bv1XAqh1YadAWHgDWgxKuhhns7T2EywG"}
]
|> Enum.flat_map(make_btc_address)
|> Enum.each(insert_on_conflict_nothing)

defmodule InsertUser do
  def run({email, username, eth_address}) do
    {:ok, user} =
      %User{
        email: email,
        username: username,
        salt:
          :crypto.strong_rand_bytes(64)
          |> Base.encode32(case: :lower)
      }
      |> Sanbase.Repo.insert(on_conflict: :nothing)

    %EthAccount{address: eth_address, user_id: user.id}
    |> Sanbase.Repo.insert(on_conflict: :nothing)
  end
end

defmodule InsertExchangeAddresses do
  alias Sanbase.Model.ExchangeAddress

  def run do
    address_data()
    |> Enum.map(&update_or_create_eth_address/1)
    |> Enum.each(&Sanbase.Repo.insert(&1, on_conflict: :nothing))
  end

  defp update_or_create_eth_address({name, address, comments, infrastructure_id}) do
    Repo.get_by(ExchangeAddress, address: address)
    |> case do
      nil ->
        %ExchangeAddress{}
        |> ExchangeAddress.changeset(%{
          address: address,
          name: name,
          comments: comments,
          infrastructure_id: infrastructure_id
        })

      exch_address ->
        exch_address
        |> ExchangeAddress.changeset(%{
          name: name,
          comments: comments,
          infrastructure_id: infrastructure_id
        })
    end
  end

  defp address_data() do
    [
      {"Binance contract owner wallet", "0x00c5e04176d95a286fcce0e68c683ca0bfec8454",
       "This is the owner of the BNB contract and is the #1 owner of BNB.", 1},
      {"Binance hot wallet", "0x3f5ce5fbfe3e9af3971dd833d26ba9b5c936f0be", nil, 1},
      {"Binance related wallet", "0xfe9e8709d3215310075d67e3ed32a380ccf451c8",
       "2nd largest BNB address. Yet to confirm relationship but it holds around 6 Billion dollars worth of tokens and most tokens are Binance related. Transfers to Binance rather often. Could be unidentified binance wallet #2. Or maybe....",
       1},
      {"Bitfinex cold wallet (?)", "0xf4B51B14b9EE30dc37EC970B50a486F37686E2a8", nil, 1},
      {"Bitfinex", "0x7180EB39A6264938FDB3EfFD7341C4727c382153", nil, 1},
      {"Bitfinex wallet1", "0x1151314c646ce4e0efd76d1af4760ae66a9fe30f", "Verified by etherscan",
       1},
      {"Bitfinex wallet2", "0x7727e5113d1d161373623e5f49fd568b4f543a9e", "Verified by etherscan",
       1},
      {"Bitfinex wallet3", "0x4fdd5eb2fb260149a3903859043e962ab89d8ed4", "Verified by etherscan",
       1},
      {"Bitfinex wallet4", "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa", "Verified by etherscan",
       1},
      {"Bitfinex old wallet", "0xcafb10ee663f465f9d10588ac44ed20ed608c11e",
       "Verified by etherscan", 1},
      {"Bittrex", "0xfbb1b73c4f0bda4f67dca266ce6ef42f520fbb98", nil, 1},
      {"Bittrex_2", "0xE94b04a0FeD112f3664e45adb2B8915693dD5FF3", nil, 1},
      {"coinexchange.io", "0x4b01721f0244e7c5b5f63c20942850e447f5a5ee", nil, 1},
      {"etherdelta_2", "0x8d12a197cb00d4747a1fe03395095ce2a5cc6819", nil, 1},
      {"IDEX_1", "0x2a0c0dbecc7e4d658f48e01e3fa353f44050c208", nil, 1},
      {"Kraken_1", "0x2910543af39aba0cd09dbb2d50200b3e800a63d2", nil, 1},
      {"Kraken_2", "0x0a869d79a7052c7f1b55a8ebabbea3420f0d1e13", nil, 1},
      {"Kraken_3", "0xe853c56864a2ebe4576a807d26fdc4a0ada51919", nil, 1},
      {"Kraken_4", "0x267be1c1d684f78cb4f6a176c4911b741e4ffdc0", nil, 1},
      {"KrakenREP", "0xA2a8f158aed54CE9A73d41EEEc23Bf3a51b5654D", nil, 1},
      {"liqui.io", "0x8271b2e8cbe29396e9563229030c89679b9470db", nil, 1},
      {"liqui.io_2", "0x5E575279bf9f4acf0A130c186861454247394C06", nil, 1},
      {"Poloniex coldwallet", "0xb794f5ea0ba39494ce839613fffba74279579268",
       "Verified by etherscan", 1},
      {"Poloniex wallet1", "0x32be343b94f860124dc4fee278fdcbd38c102d88", "Verified by etherscan",
       1},
      {"Poloniex's $REP wallet address", "0xab11204cfeaccffa63c2d23aef2ea9accdb0a0d5", nil, 1},
      {"Poloniex-GNT", "0x0536806df512D6cDDE913Cf95c9886f65b1D3462", nil, 1},
      {"Poloniex's $ZRX wallet", "0xead6be34ce315940264519f250d8160f369fa5cd", nil, 1},
      {"Poloniex's contract address that transfers all incoming funds to Polo wallet1",
       "0x209c4784ab1e8183cf58ca33cb740efbf3fc18ef", nil, 1},
      {"Poloniex's Gnosis (GNO) wallet", "0x48d466b7c0d32b61e8a82cd2bcf060f7c3f966df", nil, 1},
      {"Shapeshift", "0x70faa28a6b8d6829a4b1e649d26ec9a2a39ba413", nil, 1},
      {"Yobit", "0xf5bec430576ff1b82e44ddb5a1c93f6f9d0884f3", nil, 1},
      {"yunbi_1", "0xd94c9ff168dc6aebf9b6cc86deff54f3fb0afc33", nil, 1}
    ]
  end
end

InsertExchangeAddresses.run()
InsertUser.run({"John Doe", "john.d@santiment.net", "0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a"})
