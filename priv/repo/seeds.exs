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

make_project = fn ({name, ticker, logo_url, coinmarkecap_id, infrastructure_code}) ->
  infrastructure = case infrastructure_code do
    "ETH" -> infrastructure_eth
    nil -> infrastructure_eth
    _ -> Infrastructure.get_or_insert(infrastructure_code)
  end

  %Project{ name: name,
	    ticker: ticker,
	    logo_url: logo_url,
	    coinmarketcap_id: coinmarkecap_id,
	    infrastructure: infrastructure
  }
end

make_btc_address = fn ({name, address}) ->
  [
    %ProjectBtcAddress{
      project: Repo.get_by(Project, name: name),
      address: address
    }
  ]
end

make_eth_address = fn ({name, address}) ->
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
  {"EOS","EOS","eos.png","eos","ETH"},
  {"Golem","GNT","golem.png","golem-network-tokens","ETH"},
  {"Iconomi","ICN","iconomi.png","iconomi","ETH"},
  {"Gnosis","GNO","gnosis.png","gnosis-gno","ETH"},
  {"Status","SNT","status.png","status","ETH"},
  {"TenX","PAY","tenx.png","tenx","ETH"},
  {"Basic Attention Token","BAT","basic-attention-token.png","basic-attention-token","ETH"},
  {"Populous","PPT","populous.png","populous","ETH"},
  {"DigixDAO","DGD","digixdao.png","digixdao","ETH"},
  {"Bancor","BNT","bancor.png","bancor","ETH"},
  {"MobileGo","MGO","mobilego.png","mobilego","ETH"},
  {"Aeternity","AE","aeternity.png","aeternity","ETH"},
  {"SingularDTV","SNGLS","singulardtv.png","singulardtv","ETH"},
  {"Civic","CVC","civic.png","civic","ETH"},
  {"Aragon","ANT","aragon.png","aragon","ETH"},
  {"FirstBlood","1ST","firstblood.png","firstblood","ETH"},
  {"Etheroll","DICE","etheroll.png","etheroll","ETH"},
  {"Melon","MLN","melon.png","melon","ETH"},
  {"iExec RLC","RLC","rlc.png","rlc","ETH"},
  {"Stox","STX","stox.png","stox","ETH"},
  {"Humaniq","HMQ","humaniq.png","humaniq","ETH"},
  {"Polybius","PLBT","polybius.png","polybius","ETH"},
  {"Santiment","SAN","santiment.png","santiment","ETH"},
  {"district0x","DNT","district0x.png","district0x","ETH"},
  {"DAO.Casino","BET","dao-casino.png","dao-casino","ETH"},
  {"Centra","CTR","centra.png","centra","ETH"},
  {"Tierion","TNT","tierion.png","tierion","ETH"},
  {"Matchpool","GUP","guppy.png","guppy","ETH"}
]
|> Enum.map(make_project)
|> Enum.each(&Repo.insert!/1)


[
  {"EOS","0x10F0c9112b255507701df1b1be5D8dcd9A82bb5e"},
  {"Golem","0x7da82c7ab4771ff031b66538d2fb9b0b047f6cf9"},
  {"Iconomi","0x154Af3E01eC56Bc55fD585622E33E3dfb8a248d8"},
  {"Gnosis","0x851b7F3Ab81bd8dF354F0D7640EFcD7288553419"},
  {"Status","0xA646E29877d52B9e2De457ECa09C724fF16D0a2B"},
  {"TenX","0x185f19B43d818E10a31BE68f445ef8EDCB8AFB83"},
  {"Basic Attention Token","0x44fcfaBfBe32024a01b778c025D70498382CCEd0"},
  {"Populous","0xca48BA80Cfa6CC06963B62AeE48000f031c7E2dC"},
  {"DigixDAO","0xf0160428a8552ac9bb7e050d90eeade4ddd52843"},
  {"Bancor","0x5894110995B8c8401Bd38262bA0c8EE41d4E4658"},
  {"MobileGo","0x6d7ea347ef837462a55337C4f772868F2A80B863"},
  {"Aeternity","0x15c19E6c203E2c34D1EDFb26626bfc4F65eF96F0"},
  {"SingularDTV","0x5901Deb2C898D5dBE5923E05e510E95968a35067"},
  {"Civic","0x2323763D78bF7104b54A462A79C2Ce858d118F2F"},
  {"Aragon","0xcafE1A77e84698c83CA8931F54A755176eF75f2C"},
  {"FirstBlood","0xa5384627F6DcD3440298E2D8b0Da9d5F0FCBCeF7"},
  {"Etheroll","0x24C3235558572cff8054b5a419251D3B0D43E91b"},
  {"Melon","0x8615F13C12c24DFdca0ba32511E2861BE02b93b2"},
  {"iExec RLC","0x21346283a31A5AD10Fa64377E77A8900Ac12d469"},
  {"Stox","0x3dD88B391fe62a91436181eD2D43E20B86CDE60c"},
  {"Humaniq","0xa2c9a7578e2172f32a36c5c0e49d64776f9e7883"},
  {"Polybius","0xe9Eca8bB5e61e8e32f26B5E8c117561F68084a9C"},
  {"Santiment","0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a"},
  {"district0x","0xd20E4d854C71dE2428E1268167753e4C7070aE68"},
  {"DAO.Casino","0x1446bf7AF9dF857b23a725646D94f9Ec49802227"},
  {"Centra","0x96A65609a7B84E8842732DEB08f56C3E21aC6f8a"},
  {"Tierion","0x0C4b367e876d18d5c102023D9240DD7e9C11b380"},
  {"Matchpool","0x1c10aD0b5f1b4013173f05B4cc05a60cBBAa6536"}
]
|> Enum.flat_map(make_eth_address)
|> Enum.each(&Repo.insert!/1)


#######################################
# Projecttransparency projects
#######################################

[
  {"CFI","Cofound.it","cofound-it.png","cofound-it","ETH"},
  {"Dappbase","DAP",nil,nil,"ETH"},
  {"Encrypgen","DNA",nil,"encrypgen","ETH"},
  {"Etherisc","RSC",nil,nil,"ETH"},
  {"Expanse/Tokenlab","EXP/LAB","expanse.png","expanse","ETH"},
  {"Gatcoin.ioCFI","GAT",nil,nil,"ETH"},
  {"Hshare","HSR","hshare.png","hshare","ETH"},
  {"Indorse","IND","indorse-token.png","indorse-token","ETH"},
  {"Lykke","LKK","lykke.png","lykke","ETH"},
  {"Maecenas","ART","maecenas.png","maecenas","ETH"},
  {"Musiconomi","MCI","musiconomi.png","musiconomi","ETH"},
  {"Virgil Capital","VIC",nil,nil,"ETH"}
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
  {"Musiconomi", "0xc7CD9d874F93F2409F39A95987b3E3C738313925"},
]
|> Enum.flat_map(make_eth_address)
|> Enum.each(&Repo.insert!/1)


[
  {"Encrypgen", "13MoQt2n9cHNzbpt8PfeVYp2cehgzRgj6v"},
  {"Encrypgen", "16bv1XAqh1YadAWHgDWgxKuhhns7T2EywG"}
]
|> Enum.flat_map(make_btc_address)
|> Enum.each(&Repo.insert!/1)


user = %User{
  email: "john.d@santiment.net",
  username: "John Dow",
  salt: "LgcwR3e98PR/gvgV7Ph1+ZXnw4yhTz25k08QLi/39qdCt/V0XOGlJRiL938NtJk0"
}
|> Repo.insert!

%EthAccount{address: "0x6dD5A9F47cfbC44C04a0a4452F0bA792ebfBcC9a", user_id: user.id}
|> Repo.insert!
