defmodule Mix.Tasks.LoadTest.SeedProjects do
  use Mix.Task

  alias Sanbase.Repo
  alias Sanbase.Project
  alias Sanbase.Model.Infrastructure

  @shortdoc "Seed projects for load testing"

  @moduledoc """
  Inserts a predefined set of projects with contract addresses and GitHub
  organizations for load testing against local Postgres + remote ClickHouse.

      mix load_test.seed_projects

  Idempotent — uses `ON CONFLICT DO NOTHING` on slug, so re-running is safe.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Seeding load test projects...")

    eth_infra = Infrastructure.get_or_insert("ETH")

    projects()
    |> Enum.each(fn proj_data ->
      case insert_project(proj_data, eth_infra) do
        {:ok, project} ->
          insert_contract_addresses(project, proj_data.contract_addresses)
          insert_github_organizations(project, proj_data.github_links)
          Mix.shell().info("  #{proj_data.slug} (#{proj_data.ticker})")

        {:exists, _project} ->
          Mix.shell().info("  #{proj_data.slug} (#{proj_data.ticker}) — already exists")
      end
    end)

    Mix.shell().info("\nDone! #{length(projects())} projects seeded.")
  end

  defp insert_project(proj_data, eth_infra) do
    attrs = %{
      name: proj_data.name,
      slug: proj_data.slug,
      ticker: proj_data.ticker,
      infrastructure_id: eth_infra.id
    }

    changeset = Project.changeset(%Project{}, attrs)

    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :slug) do
      {:ok, %{id: nil}} ->
        project = Repo.get_by!(Project, slug: proj_data.slug)
        {:exists, project}

      {:ok, project} ->
        {:ok, project}
    end
  end

  defp insert_contract_addresses(project, contract_addresses) do
    Enum.each(contract_addresses, fn ca ->
      Project.ContractAddress.add_contract(project, %{
        address: ca.address,
        decimals: ca.decimals
      })
    end)
  end

  defp insert_github_organizations(project, github_links) do
    Enum.each(github_links, fn link ->
      case Project.GithubOrganization.link_to_organization(link) do
        {:ok, org} ->
          Project.GithubOrganization.add_github_organization(project.id, org)

        {:error, _} ->
          :skip
      end
    end)
  end

  defp projects do
    [
      %{
        name: "Bitcoin",
        slug: "bitcoin",
        ticker: "BTC",
        contract_addresses: [],
        github_links: ["https://github.com/bitcoin"]
      },
      %{
        name: "Ethereum",
        slug: "ethereum",
        ticker: "ETH",
        contract_addresses: [%{address: "ETH", decimals: 18}],
        github_links: ["https://github.com/ethereum"]
      },
      %{
        name: "Tether [on Arbitrum]",
        slug: "arb-tether",
        ticker: "USDT",
        contract_addresses: [
          %{address: "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9", decimals: 6}
        ],
        github_links: ["https://github.com/tetherto"]
      },
      %{
        name: "Tether [on Avalanche]",
        slug: "a-tether",
        ticker: "USDT",
        contract_addresses: [
          %{address: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7", decimals: 6}
        ],
        github_links: ["https://github.com/tetherto"]
      },
      %{
        name: "Tether [on BNB]",
        slug: "bnb-tether",
        ticker: "USDT",
        contract_addresses: [
          %{address: "0x55d398326f99059ff775485246999027b3197955", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Chain-key USDT",
        slug: "chain-key-usdt",
        ticker: "CKUSDT",
        contract_addresses: [
          %{address: "0xdac17f958d2ee523a2206206994597c13d831ec7", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Tether [on Optimism]",
        slug: "o-tether",
        ticker: "USDT",
        contract_addresses: [
          %{address: "0x94b008aa00579c1307b0ef2c499ad98a8ce58e58", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Tether [on Polygon]",
        slug: "p-tether",
        ticker: "USDT",
        contract_addresses: [
          %{address: "0xc2132d05d31c914a87c6611c10748aeb04b58e8f", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Tether [on Solana]",
        slug: "sol-tether",
        ticker: "USDT",
        contract_addresses: [
          %{address: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Tether [on Ethereum]",
        slug: "tether",
        ticker: "USDT",
        contract_addresses: [
          %{address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", decimals: 6}
        ],
        github_links: ["https://github.com/tetherto"]
      },
      %{
        name: "BNB",
        slug: "binance-coin",
        ticker: "BNB",
        contract_addresses: [],
        github_links: ["https://github.com/bnb-chain", "https://github.com/binance-exchange"]
      },
      %{
        name: "XRP Ledger",
        slug: "xrp",
        ticker: "XRP",
        contract_addresses: [],
        github_links: ["https://github.com/XRPLF", "https://github.com/ripple"]
      },
      %{
        name: "USD Coin [on Arbitrum]",
        slug: "arb-usd-coin",
        ticker: "USDC",
        contract_addresses: [
          %{address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", decimals: 6}
        ],
        github_links: ["https://github.com/centrehq"]
      },
      %{
        name: "USD Coin [on Avalanche]",
        slug: "a-usd-coin",
        ticker: "USDC",
        contract_addresses: [
          %{address: "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E", decimals: 6}
        ],
        github_links: ["https://github.com/centrehq"]
      },
      %{
        name: "USD Coin [on BNB]",
        slug: "bnb-usd-coin",
        ticker: "USDC",
        contract_addresses: [
          %{address: "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Chain-key USDC",
        slug: "chain-key-usdc",
        ticker: "CKUSDC",
        contract_addresses: [
          %{address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "USD Coin [on Optimism]",
        slug: "o-usd-coin",
        ticker: "USDC",
        contract_addresses: [
          %{address: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "USD Coin [on Polygon]",
        slug: "p-usd-coin",
        ticker: "USDC",
        contract_addresses: [
          %{address: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "USD Coin [on Solana]",
        slug: "sol-usd-coin",
        ticker: "USDC",
        contract_addresses: [
          %{address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "USD Coin [on Ethereum]",
        slug: "usd-coin",
        ticker: "USDC",
        contract_addresses: [
          %{address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", decimals: 6}
        ],
        github_links: ["https://github.com/centrehq"]
      },
      %{
        name: "Solana",
        slug: "solana",
        ticker: "SOL",
        contract_addresses: [
          %{address: "So11111111111111111111111111111111111111111", decimals: 9}
        ],
        github_links: ["https://github.com/solana-labs", "https://github.com/anza-xyz"]
      },
      %{
        name: "TRON",
        slug: "tron",
        ticker: "TRX",
        contract_addresses: [],
        github_links: ["https://github.com/tronprotocol"]
      },
      %{
        name: "Dogecoin",
        slug: "dogecoin",
        ticker: "DOGE",
        contract_addresses: [],
        github_links: ["https://github.com/dogecoin"]
      },
      %{
        name: "Cardano",
        slug: "cardano",
        ticker: "ADA",
        contract_addresses: [
          %{address: "0x3ee2200efb3400fabb9aacf31297cbdd1d435d47", decimals: 6}
        ],
        github_links: [
          "https://github.com/input-output-hk",
          "https://github.com/cardano-foundation"
        ]
      },
      %{
        name: "Bitcoin Cash",
        slug: "bitcoin-cash",
        ticker: "BCH",
        contract_addresses: [],
        github_links: ["https://github.com/bitcoincashorg"]
      },
      %{
        name: "UNUS SED LEO",
        slug: "unus-sed-leo",
        ticker: "LEO",
        contract_addresses: [
          %{address: "0x2af5d2ad76741191d15dfe7bf6ac92d4bd912ca3", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Hyperliquid",
        slug: "hyperliquid",
        ticker: "HYPE",
        contract_addresses: [],
        github_links: ["https://github.com/hyperliquid-dex"]
      },
      %{
        name: "Canton",
        slug: "canton-network",
        ticker: "CC",
        contract_addresses: [],
        github_links: ["https://github.com/hyperledger-labs"]
      },
      %{
        name: "Monero",
        slug: "monero",
        ticker: "XMR",
        contract_addresses: [],
        github_links: ["https://github.com/monero-project"]
      },
      %{
        name: "ChainLink",
        slug: "chainlink",
        ticker: "LINK",
        contract_addresses: [
          %{address: "0x514910771af9ca656af840dff83e8264ecf986ca", decimals: 18}
        ],
        github_links: ["https://github.com/smartcontractkit"]
      },
      %{
        name: "Ethena USDe",
        slug: "ethena-usde",
        ticker: "USDe",
        contract_addresses: [
          %{address: "0x4c9EDD5852cd905f086C759E8383e09bff1E68B3", decimals: 18}
        ],
        github_links: ["https://github.com/ethena-labs"]
      },
      %{
        name: "Dai [on Avalanche]",
        slug: "a-multi-collateral-dai",
        ticker: "DAI",
        contract_addresses: [
          %{address: "0xd586E7F844cEa2F87f50152665BCbc2C279D8d70", decimals: 18}
        ],
        github_links: ["https://github.com/makerdao"]
      },
      %{
        name: "Dai [on Arbitrum]",
        slug: "arb-multi-collateral-dai",
        ticker: "DAI",
        contract_addresses: [
          %{address: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1", decimals: 18}
        ],
        github_links: ["https://github.com/makerdao"]
      },
      %{
        name: "Dai [on BNB]",
        slug: "bnb-multi-collateral-dai",
        ticker: "DAI",
        contract_addresses: [
          %{address: "0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Dai [on Ethereum]",
        slug: "multi-collateral-dai",
        ticker: "DAI",
        contract_addresses: [
          %{address: "0x6b175474e89094c44da98b954eedeac495271d0f", decimals: 18}
        ],
        github_links: ["https://github.com/makerdao"]
      },
      %{
        name: "Dai [on Optimism]",
        slug: "o-multi-collateral-dai",
        ticker: "DAI",
        contract_addresses: [
          %{address: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Dai [on Polygon]",
        slug: "p-multi-collateral-dai",
        ticker: "DAI",
        contract_addresses: [
          %{address: "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Stellar",
        slug: "stellar",
        ticker: "XLM",
        contract_addresses: [],
        github_links: ["https://github.com/stellar"]
      },
      %{
        name: "World Liberty Financial USD",
        slug: "usd1",
        ticker: "USD1",
        contract_addresses: [
          %{address: "0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Hedera",
        slug: "hedera-hashgraph",
        ticker: "HBAR",
        contract_addresses: [],
        github_links: ["https://github.com/hiero-ledger", "https://github.com/hashgraph"]
      },
      %{
        name: "PayPal USD",
        slug: "paypal-usd",
        ticker: "PYUSD",
        contract_addresses: [
          %{address: "0x6c3ea9036406852006290770BEdFcAbA0e23A0e8", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Litecoin",
        slug: "litecoin",
        ticker: "LTC",
        contract_addresses: [],
        github_links: ["https://github.com/litecoin-project"]
      },
      %{
        name: "Avalanche",
        slug: "avalanche",
        ticker: "AVAX",
        contract_addresses: [],
        github_links: ["https://github.com/ava-labs"]
      },
      %{
        name: "Zcash",
        slug: "zcash",
        ticker: "ZEC",
        contract_addresses: [],
        github_links: ["https://github.com/zcash"]
      },
      %{
        name: "Sui",
        slug: "sui",
        ticker: "SUI",
        contract_addresses: [],
        github_links: ["https://github.com/MystenLabs"]
      },
      %{
        name: "SHIBA INU",
        slug: "shiba-inu",
        ticker: "SHIB",
        contract_addresses: [
          %{address: "0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce", decimals: 18}
        ],
        github_links: ["https://github.com/shibaswaparmy"]
      },
      %{
        name: "Toncoin",
        slug: "toncoin",
        ticker: "TON",
        contract_addresses: [
          %{address: "0x582d872a1b094fc48f5de31d3b73f2d9be47def1", decimals: 9}
        ],
        github_links: ["https://github.com/newton-blockchain"]
      },
      %{
        name: "World Liberty Financial",
        slug: "world-liberty-financial-wlfi",
        ticker: "WLFI",
        contract_addresses: [
          %{address: "0xdA5e1988097297dCdc1f90D4dFE7909e847CBeF6", decimals: 18}
        ],
        github_links: ["https://github.com/worldliberty"]
      },
      %{
        name: "Cronos",
        slug: "crypto-com-coin",
        ticker: "CRO",
        contract_addresses: [
          %{address: "0xa0b73e1ff0b80914ab6fe0444e65848c4c34450b", decimals: 8}
        ],
        github_links: []
      },
      %{
        name: "Tether Gold",
        slug: "tether-gold",
        ticker: "XAUt",
        contract_addresses: [
          %{address: "0x68749665FF8D2d112Fa859AA293F07A622782F38", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Polkadot",
        slug: "polkadot-new",
        ticker: "DOT",
        contract_addresses: [],
        github_links: ["https://github.com/paritytech"]
      },
      %{
        name: "PAX Gold",
        slug: "pax-gold",
        ticker: "PAXG",
        contract_addresses: [
          %{address: "0x45804880de22913dafe09f4980848ece6ecbaf78", decimals: 18}
        ],
        github_links: ["https://github.com/paxosglobal"]
      },
      %{
        name: "Uniswap [on Polygon]",
        slug: "p-uniswap",
        ticker: "UNI",
        contract_addresses: [
          %{address: "0xb33eaad8d922b1083446dc23f610c2567fb5180f", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Uniswap [on Ethereum]",
        slug: "uniswap",
        ticker: "UNI",
        contract_addresses: [
          %{address: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", decimals: 18}
        ],
        github_links: ["https://github.com/uniswap"]
      },
      %{
        name: "Mantle",
        slug: "mantle",
        ticker: "MNT",
        contract_addresses: [
          %{address: "0x3c3a81e81dc49a522a592e7622a7e711c06bf354", decimals: 18}
        ],
        github_links: ["https://github.com/mantlenetworkio"]
      },
      %{
        name: "Bittensor",
        slug: "bittensor",
        ticker: "TAO",
        contract_addresses: [],
        github_links: ["https://github.com/opentensor"]
      },
      %{
        name: "MemeCore",
        slug: "bnb-memecore",
        ticker: "M",
        contract_addresses: [
          %{address: "0x22b1458e780f8fa71e2f84502cee8b5a3cc731fa", decimals: 18}
        ],
        github_links: ["https://github.com/memecore-foundation"]
      },
      %{
        name: "Global Dollar",
        slug: "global-dollar-usdg",
        ticker: "USDG",
        contract_addresses: [
          %{address: "0xe343167631d89B6Ffc58B88d6b7fB0228795491D", decimals: 6}
        ],
        github_links: ["https://github.com/paxosglobal"]
      },
      %{
        name: "Aave [on Ethereum]",
        slug: "aave",
        ticker: "AAVE",
        contract_addresses: [
          %{address: "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9", decimals: 18}
        ],
        github_links: ["https://github.com/ETHLend", "https://github.com/aave"]
      },
      %{
        name: "Aave [on Optimism]",
        slug: "o-aave",
        ticker: "AAVE",
        contract_addresses: [],
        github_links: []
      },
      %{
        name: "Aave [on Polygon]",
        slug: "p-aave",
        ticker: "AAVE",
        contract_addresses: [
          %{address: "0xd6df932a45c0f255f85145f286ea0b292b21c90b", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Aster",
        slug: "bnb-aster",
        ticker: "ASTER",
        contract_addresses: [
          %{address: "0x000Ae314E2A2172a039B26378814C252734f556A", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "OKB",
        slug: "okb",
        ticker: "OKB",
        contract_addresses: [
          %{address: "0x75231f58b43240c9718dd58b4967c5114342a86c", decimals: 18}
        ],
        github_links: []
      },
      %{name: "Pi", slug: "pi", ticker: "PI", contract_addresses: [], github_links: []},
      %{
        name: "Sky",
        slug: "sky",
        ticker: "SKY",
        contract_addresses: [
          %{address: "0x56072C95FAA701256059aa122697B133aDEd9279", decimals: 18}
        ],
        github_links: ["https://github.com/sky-ecosystem", "https://github.com/makerdao"]
      },
      %{
        name: "XinFin",
        slug: "xinfin-network",
        ticker: "XDC",
        contract_addresses: [
          %{address: "0x41ab1b6fcbb2fa9dced81acbdec13ea6315f2bf2", decimals: 18}
        ],
        github_links: ["https://github.com/xinfinorg"]
      },
      %{
        name: "Bitget Token",
        slug: "bitget-token-new",
        ticker: "BGB",
        contract_addresses: [
          %{address: "0x54D2252757e1672EEaD234D27B1270728fF90581", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "Ripple USD",
        slug: "ripple-usd",
        ticker: "RLUSD",
        contract_addresses: [
          %{address: "0x8292bb45bf1ee4d140127049757c2e0ff06317ed", decimals: 18}
        ],
        github_links: ["https://github.com/ripple"]
      },
      %{
        name: "Pepe",
        slug: "pepe",
        ticker: "PEPE",
        contract_addresses: [
          %{address: "0x6982508145454Ce325dDbE47a25d4ec3d2311933", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "NEAR Protocol",
        slug: "near-protocol",
        ticker: "NEAR",
        contract_addresses: [],
        github_links: ["https://github.com/near", "https://github.com/nearprotocol"]
      },
      %{
        name: "Ethereum Classic",
        slug: "ethereum-classic",
        ticker: "ETC",
        contract_addresses: [
          %{address: "0x3d6545b08693dae087e957cb1180ee38b9e3c25e", decimals: 18}
        ],
        github_links: ["https://github.com/ethereumclassic"]
      },
      %{
        name: "Internet Computer",
        slug: "internet-computer",
        ticker: "ICP",
        contract_addresses: [
          %{address: "0x00f3C42833C3170159af4E92dbb451Fb3F708917", decimals: 8}
        ],
        github_links: [
          "https://github.com/dfinity-lab",
          "https://github.com/dfinity",
          "https://github.com/dfinity-side-projects"
        ]
      },
      %{
        name: "Ondo",
        slug: "ondo-finance",
        ticker: "ONDO",
        contract_addresses: [
          %{address: "0xfAbA6f8e4a5E8Ab82F62fe7C39859FA577269BE3", decimals: 18}
        ],
        github_links: ["https://github.com/ondoprotocol"]
      },
      %{
        name: "POL [on Polygon]",
        slug: "p-matic-network",
        ticker: "POL",
        contract_addresses: [],
        github_links: []
      },
      %{
        name: "Polygon Ecosystem Token",
        slug: "polygon-ecosystem-token",
        ticker: "POL",
        contract_addresses: [
          %{address: "0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6", decimals: 18}
        ],
        github_links: ["https://github.com/maticnetwork"]
      },
      %{
        name: "Worldcoin [on Optimism]",
        slug: "o-worldcoin-org",
        ticker: "WLD",
        contract_addresses: [
          %{address: "0xdC6fF44d5d932Cbd77B52E5612Ba0529DC6226F1", decimals: 18}
        ],
        github_links: ["https://github.com/worldcoin"]
      },
      %{
        name: "Worldcoin [on Ethereum]",
        slug: "worldcoin-org",
        ticker: "WLD",
        contract_addresses: [
          %{address: "0x163f8C2467924be0ae7B5347228CABF260318753", decimals: 18}
        ],
        github_links: ["https://github.com/worldcoin"]
      },
      %{
        name: "USDD [on BNB Chain]",
        slug: "bnb-usdd",
        ticker: "USDD",
        contract_addresses: [
          %{address: "0x45e51bc23d592eb2dba86da3985299f7895d66ba", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "USDD [on Ethereum]",
        slug: "usdd",
        ticker: "USDD",
        contract_addresses: [
          %{address: "0x4f8e5de400de08b164e7421b3ee387f461becd1a", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "KuCoin Token",
        slug: "kucoin-shares",
        ticker: "KCS",
        contract_addresses: [
          %{address: "0xf34960d9d60be18cc1d5afc1a6f012a723a28811", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Midnight",
        slug: "midnight-network",
        ticker: "NIGHT",
        contract_addresses: [],
        github_links: ["https://github.com/midnightntwrk"]
      },
      %{
        name: "Cosmos",
        slug: "cosmos",
        ticker: "ATOM",
        contract_addresses: [],
        github_links: ["https://github.com/cosmos"]
      },
      %{
        name: "Fantom",
        slug: "fantom",
        ticker: "FTM",
        contract_addresses: [
          %{address: "0x4e15361fd6b4bb609fa63c81a2be19d873717870", decimals: 18}
        ],
        github_links: ["https://github.com/fantom-foundation"]
      },
      %{
        name: "Ethena",
        slug: "ethena",
        ticker: "ENA",
        contract_addresses: [
          %{address: "0x57e114B691Db790C35207b2e685D4A43181e6061", decimals: 18}
        ],
        github_links: ["https://github.com/ethena-labs"]
      },
      %{
        name: "Staked ENA",
        slug: "staked-ethena",
        ticker: "sENA",
        contract_addresses: [
          %{address: "0x57e114B691Db790C35207b2e685D4A43181e6061", decimals: 18}
        ],
        github_links: []
      },
      %{name: "Kaspa", slug: "kaspa", ticker: "KAS", contract_addresses: [], github_links: []},
      %{
        name: "GateToken",
        slug: "gatechain-token",
        ticker: "GT",
        contract_addresses: [
          %{address: "0xe66747a101bff2dba3697199dcce5b743b454759", decimals: 18}
        ],
        github_links: ["https://github.com/gatechain"]
      },
      %{
        name: "Flare",
        slug: "flare",
        ticker: "FLR",
        contract_addresses: [],
        github_links: ["https://github.com/flare-foundation"]
      },
      %{
        name: "OFFICIAL TRUMP",
        slug: "official-trump",
        ticker: "TRUMP",
        contract_addresses: [
          %{address: "6p6xgHyF7AeE6TZkSmFsko444wqoP15icUSqi2jfGiPN", decimals: 6}
        ],
        github_links: []
      },
      %{
        name: "Quant",
        slug: "quant",
        ticker: "QNT",
        contract_addresses: [
          %{address: "0x4a220e6096b25eadb88358cb44068a3248254675", decimals: 18}
        ],
        github_links: ["https://github.com/quantnetwork"]
      },
      %{
        name: "Algorand",
        slug: "algorand",
        ticker: "ALGO",
        contract_addresses: [],
        github_links: ["https://github.com/algorand"]
      },
      %{
        name: "Filecoin",
        slug: "file-coin",
        ticker: "FIL",
        contract_addresses: [],
        github_links: ["https://github.com/filecoin-project"]
      },
      %{
        name: "Aptos",
        slug: "aptos",
        ticker: "APT",
        contract_addresses: [],
        github_links: ["https://github.com/aptos-labs"]
      },
      %{
        name: "Render",
        slug: "render",
        ticker: "RENDER",
        contract_addresses: [
          %{address: "0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24", decimals: 18}
        ],
        github_links: ["https://github.com/rendernetwork"]
      },
      %{
        name: "Morpho",
        slug: "morpho",
        ticker: "MORPHO",
        contract_addresses: [
          %{address: "0x58D97B57BB95320F9a05dC918Aef65434969c2B2", decimals: 18}
        ],
        github_links: ["https://github.com/morpho-org"]
      },
      %{
        name: "XDC Network",
        slug: "xdc-network",
        ticker: "XDC",
        contract_addresses: [],
        github_links: []
      },
      %{
        name: "United Stables",
        slug: "bnb-united-stables",
        ticker: "U",
        contract_addresses: [
          %{address: "0xcE24439F2D9C6a2289F741120FE202248B666666", decimals: 18}
        ],
        github_links: []
      },
      %{
        name: "pippin",
        slug: "pippin",
        ticker: "PIPPIN",
        contract_addresses: [],
        github_links: ["https://github.com/yoheinakajima"]
      },
      %{
        name: "VeChain",
        slug: "vechain",
        ticker: "VET",
        contract_addresses: [
          %{address: "0xd850942ef8811f2a866692a623011bde52a462c1", decimals: 18}
        ],
        github_links: ["https://github.com/vechain"]
      },
      %{
        name: "Pump.fun",
        slug: "sol-pump-fun",
        ticker: "PUMP",
        contract_addresses: [
          %{address: "pumpCmXqMfrsAkQ5r49WcJnRayYRqmXz6ae8H7H9Dfn", decimals: 6}
        ],
        github_links: []
      }
    ]
  end
end
