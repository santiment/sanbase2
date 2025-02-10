defmodule Sanbase.Factory.Helper do
  @moduledoc false
  def rand_str(length \\ 10) do
    length |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, length)
  end

  def pseudo_random_project_data(index) do
    projects = [
      %{name: "dDAI", slug: "ddai", ticker: "DDAI"},
      %{name: "Color Platform", slug: "color-platform", ticker: "CLR"},
      %{name: "Enecuum", slug: "enecuum", ticker: "ENQ"},
      %{name: "Cosmos", slug: "cosmos", ticker: "ATOM"},
      %{name: "Gods Unchained", slug: "gods-unchained", ticker: "GUN"},
      %{name: "ZeuxCoin", slug: "zeuxcoin", ticker: "ZUC"},
      %{name: "Treelion", slug: "treelion", ticker: "TRN"},
      %{name: "Kava", slug: "kava", ticker: "KAVA"},
      %{name: "HyperExchange", slug: "hyperexchange", ticker: "HX"},
      %{name: "0x Tracker", slug: "0xtracker", ticker: "ZRT"},
      %{name: "Tepleton", slug: "tepleton", ticker: "TEP"},
      %{name: "MargiX", slug: "margix", ticker: "MGX"},
      %{name: "EOS Force", slug: "eos-force", ticker: "EOSC"},
      %{name: "YottaChain", slug: "yottachain", ticker: "YTA"},
      %{name: "Anchor", slug: "anchor", ticker: "ANCT"},
      %{name: "Versess Coin", slug: "versess-coin", ticker: "VERS"},
      %{name: "IOTA", slug: "iota", ticker: "MIOTA"},
      %{name: "VELO Token", slug: "velo-token", ticker: "VLO"},
      %{name: "7Eleven", slug: "7eleven", ticker: "7E"},
      %{name: "everiToken", slug: "everitoken", ticker: "EVT"},
      %{name: "Yap Stone", slug: "yap-stone", ticker: "YAP"},
      %{name: "Dash Cash", slug: "dash-cash", ticker: "DSC"},
      %{name: "NOVA", slug: "nova", ticker: "NOVA"},
      %{name: "Hintchain", slug: "hintchain", ticker: "HINT"},
      %{name: "Azbit", slug: "azbit", ticker: "AZ"},
      %{name: "Project WITH", slug: "project-with", ticker: "WIKEN"},
      %{name: "Chiliz", slug: "chiliz", ticker: "CHZ"},
      %{name: "Coin2Play ", slug: "coin2play", ticker: "C2P"},
      %{name: "DeepCloud AI", slug: "deepcloud-ai", ticker: "DEEP"},
      %{name: "Sessia", slug: "sessia", ticker: "KICKS"},
      %{name: "Augmint", slug: "augmint", ticker: "AUG"},
      %{name: "Catex Token", slug: "catex-token", ticker: "CATT"},
      %{name: "Lambda Space Token", slug: "lambda-space-token", ticker: "LAMBS"},
      %{name: "Helena", slug: "helena", ticker: "HLN"},
      %{name: "Bitfex", slug: "bitfex", ticker: "BFX"},
      %{name: "merkleX", slug: "merklex", ticker: "MKX"},
      %{name: "HUSD", slug: "husd", ticker: "HUSD"},
      %{name: "DAD", slug: "dad-chain", ticker: "DAD"},
      %{name: "MeconCash", slug: "meconcash", ticker: "MCH"},
      %{name: "GateToken", slug: "gatechain-token", ticker: "GT"},
      %{name: "Muse", slug: "muse", ticker: "MUSE"},
      %{name: "MB8 Coin", slug: "mb8-coin", ticker: "MB8"},
      %{name: "Swapcoinz", slug: "swapcoinz", ticker: "SPAZ"},
      %{name: "ChronoCoin", slug: "chronocoin", ticker: "CRN"},
      %{name: "Nitrogen Network", slug: "nitrogen", ticker: "NGN"},
      %{name: "REPO", slug: "repo", ticker: "REPO"},
      %{name: "Ravencoin", slug: "ravencoin", ticker: "RVN"},
      %{name: "Rentberry", slug: "rentberry", ticker: "BERRY"},
      %{name: "Santiment", slug: "santiment", ticker: "SAN"},
      %{name: "Asura Coin", slug: "asura-coin", ticker: "ASA"},
      %{name: "HYCON ", slug: "hycon", ticker: "HYC"},
      %{name: "Steem", slug: "steem", ticker: "STEEM"},
      %{name: "zLOT Finance", slug: "zlot-finance", ticker: "ZLOT"},
      %{name: "Bitcoin Private", slug: "bitcoin-private", ticker: "BTCP"},
      %{name: "Sharpe Platform Token", slug: "sharpe-platform-token", ticker: "SHP"},
      %{name: "LBRY Credits", slug: "library-credit", ticker: "LBC"},
      %{name: "Seal Finance", slug: "seal-finance", ticker: "SEAL"},
      %{name: "ALBOS", slug: "albos", ticker: "ALB"},
      %{name: "Waletoken", slug: "waletoken", ticker: "WTN"},
      %{name: "Rocket Pool", slug: "rocket-pool", ticker: "RPL"},
      %{name: "BABB", slug: "babb", ticker: "BAX"},
      %{name: "Zilliqa", slug: "zilliqa", ticker: "ZIL"},
      %{name: "XMax", slug: "xmax", ticker: "XMX"},
      %{name: "Binance Coin", slug: "binance-coin", ticker: "BNB"},
      %{name: "WeTrust", slug: "trust", ticker: "TRST"},
      %{name: "Vivid Coin", slug: "vivid-coin", ticker: "VIVID"},
      %{name: "Refereum", slug: "refereum", ticker: "RFR"},
      %{name: "TRON", slug: "tron", ticker: "TRX"},
      %{name: "Pigeoncoin", slug: "pigeoncoin", ticker: "PGN"},
      %{name: "Genesis Vision", slug: "genesis-vision", ticker: "GVT"},
      %{name: "THEKEY", slug: "thekey", ticker: "TKY"},
      %{name: "Sakura Bloom", slug: "sakura-bloom", ticker: "SKB"},
      %{name: "NeoWorld Cash", slug: "neoworld-cash", ticker: "NASH"},
      %{name: "Fiii", slug: "fiii", ticker: "FIII"},
      %{name: "SUQA", slug: "suqa", ticker: "SUQA"},
      %{name: "Kalkulus", slug: "kalkulus", ticker: "KLKS"},
      %{name: "Nano", slug: "nano", ticker: "NANO"},
      %{name: "More Coin", slug: "more-coin", ticker: "MORE"},
      %{name: "Blocklancer", slug: "blocklancer", ticker: "LNC"},
      %{name: "QASH", slug: "qash", ticker: "QASH"},
      %{name: "indaHash", slug: "indahash", ticker: "IDH"},
      %{name: "Proxeus", slug: "proxeus", ticker: "XES"},
      %{name: "Stellar", slug: "stellar", ticker: "XLM"},
      %{name: "ACChain", slug: "acchain", ticker: "ACC"},
      %{name: "SynLev", slug: "synlev", ticker: "SYN"},
      %{name: "Bottos", slug: "bottos", ticker: "BTO"},
      %{name: "Nobrainer Finance", slug: "nobrainer-finance", ticker: "BRAIN"},
      %{name: "Bytecoin", slug: "bytecoin-bcn", ticker: "BCN"}
    ]

    if index > length(projects) do
      %{slug: rand_str(8), ticker: 4 |> rand_str() |> String.upcase(), name: rand_str(10)}
    else
      Enum.at(projects, index)
    end
  end

  def rand_address("xrp") do
    Enum.random([
      "r9vbV3EHvXWjSkeQ6CAcYVPGeq7TuiXY2X",
      "rUrdFHbrEKWNQQ444zcTLrThjcnHCw2FPu",
      "r49nVgaYSDuU7GEQh4mF1nyjsXSVRcUHsr",
      "rphasxS8Q5p5TLTpScQCBhh5HfJfPbM2M8",
      "rKWFsTLRPrgC8KDC7fCqQRzDsvajgcM1Tp",
      "rn8rUkteSFCL5gbi563RPYWew9mMqPhVGD",
      "rHAAGfqnBYxrUVYnqYyKcRESNyg8pqJdgN",
      "rJWnjUKWGJBZrJAZRGZtso7gQk6T2Wv6We",
      "r9YoMBhhQbEA8jsvHnWhAM8tdpN4xYrb8B",
      "rsWxmCo4ghqb5h1dsphKU1V1EKsMYSpXjQ",
      "rP8np2qeg88Sr1rCxc86y9KuCCnvv8854u",
      "rsK1CYzQqzc1xJ1L33pNjj26MPNVsT9RWz",
      "r3MeEnYZY9fAd5pGjAWf4dfJsQBVY9FZRL",
      "r3NqSG5o5iKTPKMqaR1xmCVvmEcSC3nmKn",
      "r3PDtZSa5LiYp1Ysn1vMuMzB59RzV3W9QH",
      "r3SRtN5Nt4uyLj2XhNhUGMBekTLkfBMPWS",
      "r3T3kYf2oGequEHvT7M4F6byeE2PzxwP5E",
      "r3kmLJN5D28dHuH8vZNUZpMC43pEHpaocV",
      "r3knww8JXufhM4R5uYdUCWScMYWGzSBsN3"
    ])
  end

  def rand_address("ethereum") do
    Faker.Blockchain.Ethereum.address()
  end

  def rand_interval do
    ([1, 3, 5, 10, 12, 60] |> Enum.random() |> to_string()) <>
      Enum.random(["m", "h", "d", "w"])
  end

  def rand_trigger_settings(rand_project, rand_erc20_project) do
    Enum.random([
      %{
        type: "metric_signal",
        metric: "social_volume_total",
        target: %{text: "random text"},
        channel: "telegram",
        operation: %{above: 300}
      },
      %{
        type: "metric_signal",
        metric: "social_volume_total",
        target: %{slug: "bitcoin text"},
        channel: ["telegram", "email"],
        operation: %{above: 5000}
      },
      %{
        type: "metric_signal",
        metric: "mvrv_usd_intraday",
        target: %{slug: rand_project.().slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{below: 40}
      },
      %{
        type: "metric_signal",
        metric: "active_addresses_24h",
        target: %{slug: rand_project.().slug},
        channel: ["telegram", "email"],
        time_window: "2d",
        operation: %{above: 1000}
      },
      %{
        type: "wallet_movement",
        selector: %{infrastructure: "ETH", slug: rand_erc20_project.().slug},
        target: %{address: rand_address("ethereum")},
        channel: "telegram",
        time_window: "1d",
        operation: %{amount_up: 200.0}
      },
      %{
        type: "wallet_movement",
        selector: %{infrastructure: "XRP", currency: "BTC"},
        target: %{address: rand_address("xrp")},
        channel: "telegram",
        time_window: "1d",
        operation: %{amount_down: 50.0}
      }
    ])
  end
end
