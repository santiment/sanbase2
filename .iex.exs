import Ecto.Query, only: [from: 2]

alias Sanbase.Model.{
  Infrastructure,
  MarketSegment,
  LatestCoinmarketcapData,
  ProjectTransparencyStatus,
  ModelUtils,
  ProjectBtcAddress,
  Currency,
  ExchangeAddress,
  Ico,
  IcoCurrencies,
  ProjectEthAddress,
  Project,
  LatestBtcWalletData
}

alias Sanbase.Auth.{
  User,
  EthAccount,
  Apikey,
  Hmac,
  UserApikeyToken
}

alias Sanbase.Voting.{
  Post,
  Poll,
  Vote,
  Tag,
  PostImage
}

alias Sanbase.UserLists.{
  UserList,
  ListItem
}

alias Sanbase.Blockchain.{
  BurnRate,
  DailyActiveAddresses,
  ExchangeFundsFlow,
  TransactionVolume
}

alias Sanbase.Clickhouse.{
  EthTransfers,
  EthDailyActiveAddresses,
  Erc20DailyActiveAddresses,
  Erc20Transfers,
  MarkExchanges,
  Erc20TransactionVolume
}

alias Sanbase.{
  Repo,
  TimescaleRepo,
  ClickhouseRepo,
  Timescaledb,
  FileStore,
  DateTimeUtils,
  ApplicationUtils,
  Parallel,
  MandrillApi
}

alias Sanbase.InternalServices.{
  Ethauth,
  Parity,
  TechIndicators
}

alias Sanbase.ExternalServices.Coinmarketcap.{
  GraphData,
  PricePoint,
  Scraper,
  TickerFetcher,
  Ticker
}

alias Sanbase.ExternalServices.Coinmarketcap2.{
  GraphData2,
  PricePoint2,
  Scraper2,
  TickerFetcher2,
  Ticker2
}

alias Sanbase.ExternalServices.Etherscan.Requests, as: EtherscanRequests
alias Sanbase.ExternalServices.Etherscan.Scraper, as: EtherscanScraper
alias Sanbase.ExternalServices.ProjectInfo
alias Sanbase.Oauth2.Hydra

alias Sanbase.Influxdb.Measurement
alias Sanbase.Influxdb.Store, as: InfluxdbStore

alias Sanbase.Discourse.Api, as: DiscourseApi
alias Sanbase.Discourse.Config, as: DiscourseConfig

alias Sanbase.Notifications.Notification
alias Sanbase.Notifications.Insight, as: NotificationsInsight
alias Sanbase.Notifications.PriceVolumeDiff, as: PriceVolumeDiff
alias Sanbase.Notifications.Type, as: NotificationsType
alias Sanbase.Notifications.Utils, as: NotificationsUtils
alias Sanbase.Notifications.Discord.DaaSignal
alias Sanbase.Notifications.Discord.ExchangeInflow
alias Sanbase.Notifications.Discord

alias Sanbase.Utils.{
  JsonLogger,
  Config,
  Math
}

alias SanbaseWeb.Graphql.Schema

alias SanbaseWeb.Graphql.Resolvers.{
  AccountResolver,
  ApikeyResolver,
  EthAccountResolver,
  ElasticsearchResolver,
  EtherbiResolver,
  FileResolver,
  GithubResolver,
  IcoResolver,
  MarketSegmentResolver,
  PostResolver,
  PriceResolver,
  ProjectBalanceResolver,
  ProjectResolver,
  ProjectTransactionsResolver,
  TechIndicatorsResolver,
  TwitterResolver,
  UserListResolver,
  VotingResolver,
  ClickhouseResolver
}

alias SanbaseWeb.Graphql.Helpers.Cache
alias SanbaseWeb.Graphql.Helpers.Utils, as: GraphUtils
alias Sanbase.Prices.Store, as: PricesStore
alias Sanbase.Prices.Utils, as: PricesUtils
alias Sanbase.Clickhouse.Common, as: ClickhouseCommon

alias Sanbase.SocialData

now = fn -> Timex.now() end
days_ago = fn days -> Timex.shift(Timex.now(), days: -days) end

project_slugs =
  from(p in Project, where: not is_nil(p.coinmarketcap_id), select: p.coinmarketcap_id)
  |> Repo.all()

project_contracts =
  from(p in Project, where: not is_nil(p.main_contract_address), select: p.main_contract_address)
  |> Repo.all()
