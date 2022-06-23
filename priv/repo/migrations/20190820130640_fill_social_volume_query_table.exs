defmodule Sanbase.Repo.Migrations.FillSocialVolumeQueryTable do
  use Ecto.Migration
  alias Sanbase.Model.Project

  def up do
    setup()

    projects_map = projects()
    data_map = data()

    data =
      Enum.map(data_map, fn {slug, query} ->
        case Map.get(projects_map, slug) do
          nil -> nil
          %Project{} = project -> %{project_id: project.id, query: query}
        end
      end)
      |> Enum.reject(&is_nil/1)

    Sanbase.Repo.insert_all(Project.SocialVolumeQuery, data, on_conflict: :nothing)
  end

  def down do
    :ok
  end

  defp setup() do
    Application.ensure_all_started(:tzdata)
  end

  defp projects() do
    Project.List.projects()
    |> Enum.map(fn %Project{coinmarketcap_id: slug} = project ->
      {slug, project}
    end)
    |> Map.new()
  end

  defp data() do
    [
      {"dragonchain", "DRGN OR dragon OR dragonchain OR dbc OR snov OR nebl OR sphtx"},
      {"wax", "wax OR \"Worldwide Asset eXchange\""},
      {"wrapped-bitcoin", "\"wrapped bitcoin\" OR \"wrapped btc\" OR wbtc"},
      {"rate3", "rte OR rate3 OR \"rate 3\""},
      {"odem", "odem OR ode"},
      {"xriba", "xriba OR xra"},
      {"zilliqa", "zil OR zilliqa OR ziliqa OR zilika OR zillika OR zill"},
      {"the-abyss", "abyss OR abys OR abis OR abiss"},
      {"chainlink", "chainlink OR (chain AND link) OR blockchainlink"},
      {"gemini-dollar", "gemini OR gusd"},
      {"contentbox", "contentbox"},
      {"smart-bitcoin", "rbtc OR \"smart bitcoin\""},
      {"universa", "universa OR utnp"},
      {"nucleus-vision", "nucleus OR ncash"},
      {"zcash", "zcash OR (z AND cash) OR zec OR zcashdash OR zcashd"},
      {"waltonchain", "wtc OR waltonchain"},
      {"digixdao",
       "DGD OR digixdao OR digix OR digixio OR digixgold OR dgddgx OR digixcor OR digixglob OR dgddao OR digidao"},
      {"melon", "melon OR mln"},
      {"siacoin", "sc OR siacoin OR (sia AND coin)"},
      {"ripple",
       "xrp OR rippl OR xrpp OR xrpa OR ripplesxrp OR xrpt OR ripple OR ripplei OR ripplea OR rippley OR ripplet OR ripplesxrp OR cripple OR crippl"},
      {"basic-attention-token",
       "bat OR batbat OR tbat OR (basic AND attention AND token) OR (basic AND token) OR BATProject OR (BAT AND Project) OR attentiontoken OR bravebat OR brave OR ethbat"},
      {"blockv", "vee OR blockv OR blockvee"},
      {"dash",
       "dash OR dashdash OR dashzcash OR dashxmr OR zdash OR drkdash OR dashorzec OR dashmonero OR dashdarkcoin OR dashcoin OR zcashdash"},
      {"nem", "nem OR xem OR nemxem OR xemnem OR nemcoin OR pacnem OR xemusd OR nemt OR nemio"},
      {"origintrail",
       "origintrail OR (origin AND trail) OR trac OR (origin AND trac) OR rorigintrail OR originalchain"},
      {"factom", "fct OR factom OR factum"},
      {"aurora", "aoa OR aurora OR avrora) "},
      {"neo", "neo OR neoomg OR neorpx OR gasneo OR neoiota"},
      {"wanchain",
       "WAN OR Wanchain OR wana OR wanchai OR listwanchain OR rwanchain OR aion OR vchain OR wannchain OR brainchain OR cswnchain OR whenchain OR wannb"},
      {"litecoin",
       "ltc OR ltcltc OR ltcxlm OR ltch OR btcltc OR litecoin OR litecoin OR litcoin OR litecoim OR litecoinlitecoin OR litecoi OR llitecoin"},
      {"funfair", "fun OR funfair"},
      {"hydro-protocol", "\"hydro protocol\" OR hydro"},
      {"dai", "dai"},
      {"project-pai", "pai NOT pchain"},
      {"aeternity", "ae OR aeternity OR aecoin OR aetoken) "},
      {"bitshares", "bts OR bitshares OR (bit AND shares)"},
      {"v-systems", "vsys or \"v systems\""},
      {"mobilego", "mobilego OR mgo or \"mobile go\""},
      {"spankchain", "spank OR spankchain OR booty OR spankbank OR spankpay"},
      {"kleros", "kleros OR pnk"},
      {"santiment",
       "(SAN OR santiment OR santoken OR santimentnet OR sancoin OR sansan OR sancoin) AND !((san AND francisco) OR (san AND fran) OR (san AND diego) OR (san AND marino) OR (san AND jose))"},
      {"internet-node-token", "int or \"internet node token\""},
      {"waves", "waves OR wvs"},
      {"ethereum",
       "eth OR ethwtc OR ether OR btcethereum OR ethfct OR ethl OR ethereum OR etheruem OR ethereumvm OR ethereuum OR ethereumit OR ethereumi NOT cash NOT gold NOT classic"},
      {"omisego", "omg OR omise OR omisego OR omiseomise"},
      {"maker", "maker OR mkr OR makerdao OR (maker AND dao)"},
      {"content-neutrality-network", "\"content neutrality network\" OR cnn"},
      {"data", "dta"},
      {"bytecoin-bcn", "bcn OR bytecoin OR (byte AND coin)"},
      {"vetri", "vld OR vetri"},
      {"callisto-network", "callisto OR calisto OR kalisto OR kallisto OR calissto OR clo"},
      {"iota",
       "iota OR iotaraiblock OR iotamiota OR xlmiota OR iotaomg OR neoiota OR miota OR xlmiota OR kiota OR giota OR tiota OR iotamiota"},
      {"aion", "chat_id"},
      {"ethereum-classic",
       "etc OR ((ethereum OR eth) AND classic) OR (eth AND classic) OR ethereumclassic OR ethereumclass OR ethereumfork OR ethereumcash OR ethfork OR (fork AND (ethereum OR eth))"},
      {"ontology",
       "ONT OR ontology OR ontolog OR ontologynetwork OR porchain OR lun OR qlc OR ontologybas OR ontologynew"},
      {"on-live", "on.live OR onlive OR onl"},
      {"essentia", "essentia OR ess OR esentia"},
      {"vechain", "vechain OR vet OR ven OR (ve AND chain)"},
      {"yoyow", "yoyow"},
      {"atonomi", "atonomi OR atmi"},
      {"bnktothefuture", "bnktothefuture OR bft"},
      {"rif-token", "rif"},
      {"aragon", "aragon OR ant"},
      {"tezos",
       "tezos OR xtz OR xtzxtz OR tezo OR tezoshub OR tezosch OR tezosfound OR tezoz OR tezoseo"},
      {"golem-network-tokens", "golem OR gnt"},
      {"stellar",
       "stellar OR lumen OR xlmstellar OR xrpstellar OR stellarterm OR lumensxlm OR xlm OR xlmxrp OR reqxlm OR reqvenxlm"},
      {"banyan-network", "banyan OR bbn OR banian"},
      {"blockpass", "blockpass OR pass"},
      {"dogecoin", "doge OR dogecoin OR dogcoin OR (dog AND coin) OR newdogecoin OR mydogecoin"},
      {"enjin-coin", "enjin OR enj OR engin"},
      {"dadi", "dadi"},
      {"credits", "(credits AND token) OR cs"},
      {"kyber-network",
       "KNC OR Kyber OR kncminer OR avalon OR cointerra OR spoondooliestech OR neptun OR kybernetwork OR airswap OR airswapio OR bancor OR homekybernetwork"},
      {"icon", "icx OR icon OR icn) "},
      {"decentraland", "mana OR decentraland"},
      {"yeed", "yggdrash OR yeed"},
      {"bitcoin-interest", "\"bitcoin interest\" OR bci"},
      {"time-new-bank", "tnb OR \"time new bank\""},
      {"tether", "tether OR usdt OR tetherusdt OR tetherfiat"},
      {"mithril", "mithril OR mith"},
      {"request", "req OR request"},
      {"qtum", "qtum"},
      {"status", "snt"},
      {"seer", "seer"},
      {"bancor", "bancor OR bnt OR bankor"},
      {"paxos-standard-token", "pax OR paxos OR paksos OR paxes"},
      {"dether", "dether OR dth"},
      {"eidoo", "eido OR eidoo OR edo"},
      {"bittorrent", "bittorrent OR btt OR bitorent OR bittorent OR bitorrent"},
      {"tron", "trx OR tron OR thron OR tronix"},
      {"medical-chain", "medicalchain OR mtn OR \"medical chain\""},
      {"rlc", "rlc OR iexec"},
      {"consensus", "sen OR consensus OR consensys"},
      {"omni", "omni"},
      {"gonetwork", "gonetwork OR got OR \"go network\""},
      {"decred", "decred OR dcr"},
      {"lisk", "lsk OR lisk OR lizk OR lissk"},
      {"bitcoin-sv", "bitcoin AND sv OR bitcoinsv OR bsv NOT cash"},
      {"bitcoin-diamond", "bcd OR (bitcoin AND diamond NOT gold NOT cash) OR bitcoindiamond"},
      {"iostoken", "iost"},
      {"eos", "eos OR eosi OR eoseth OR eostezo OR eosown OR eosusd"},
      {"ripio-credit-network", "ripio OR rcn"},
      {"cortex", "cortex OR ctxc OR kortex"},
      {"digibyte", "dgb OR digibyte OR (digi AND byte)"},
      {"wepower", "wpr OR wepower"},
      {"loopring", "loopring OR lrc"},
      {"0x", "ZRX OR 0x OR ox OR dnt OR dntzrx OR lrc"},
      {"storj", "storj"},
      {"tokencard", "tkn OR tokencard OR \"token card\""},
      {"utrust", "utk OR utrust"},
      {"ors-group", "ors"},
      {"augur", "rep OR augur"},
      {"wollo", "wollo OR wlo"},
      {"raiden-network-token", "raiden OR rdn"},
      {"singulardtv", "singulardtv OR sngls OR \"singular dtv\" OR breaker"},
      {"streamr-datacoin", "streamr OR datacoin"},
      {"bitcoin-gold", "bitcoin AND gold OR bitcoingold OR btg"},
      {"auctus", "auctus OR auc"},
      {"metaverse", "metaverse OR etp"},
      {"aventus", "aventus OR avt"},
      {"digix-gold-token", "\"digix gold token\" OR dgx OR \"digix gold\""},
      {"usd-coin", "usdcoin OR usdc OR (usd AND coin)"},
      {"poa-network", "poa"},
      {"monero",
       "monero OR xmr OR moneroxmr OR xmrmonero OR monerocoin OR monerox OR monerocash"},
      {"pundi-x", "npxs OR pundi OR pundy NOT nem"},
      {"stasis-eurs", "stasis OR eurs"},
      {"bitcoin-cash-abc", "\"bitcoin cash abc\" OR bchabc"},
      {"fusion", "fusion OR fsn"},
      {"0chain", "zcn OR 0chain"},
      {"meetone", "meetone OR meet.oneE"},
      {"aelf", "aelf OR elf"},
      {"binance-coin", "binance AND (coin OR token) OR bnb"},
      {"bitcoin-cash",
       "bch OR bcc OR bchbcc OR bchbch OR bth OR \"bitcoin cash\" OR bitcoincash OR bitoincash OR bchbitcoincash OR ebitcoincash OR coincash"},
      {"autonio", "autonio OR nio"},
      {"matrix-ai-network", "man OR matrix"},
      {"trueusd", "trueusd OR tusd OR (true AND usd)"},
      {"nano", "nano NOT technology"},
      {"aidcoin", "aidcoin"},
      {"cindicator", "cindicator OR cnd OR cindikator"},
      {"singularitynet", "singularitynet OR agi OR \"singularity net\""},
      {"qash", "qash"},
      {"verge",
       "xvg OR verge OR xvgtrx OR verg OR xvgci OR xvgfam OR verger OR vergeet OR vergelif OR vergebul OR vergexvg"},
      {"cardano",
       "ada OR cardano OR cardanoeo OR cardanoada OR adacardano OR cardanoeo OR ada OR adacardano OR cardanoada OR cardanopric"},
      {"polymath-network", "poly OR polymath"},
      {"commerceblock", "commerceblock OR cbt"},
      {"bitcoin",
       "btc OR btcsome OR btcan OR btcl OR xyzbtc OR bitcoin OR bitcon OR bicoin OR bitoin OR bitcion OR bitcoincurr NOT gold NOT cash NOT classic"},
      {"lympo", "limpo OR lympo OR lym"}
    ]
    |> Map.new()
  end
end
