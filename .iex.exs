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
  IcoCurrency,
  ProjectEthAddress,
  Project,
  LatestBtcWalletData
}

alias Sanbase.Auth.{
  User,
  EthAccount,
  Apikey,
  Hmac,
  UserApikeyToken,
  UserSettings,
  Settings
}

alias Sanbase.Tag

alias Sanbase.Vote

alias Sanbase.Insight.{
  Post,
  PostImage
}

alias Sanbase.UserList
alias Sanbase.UserList.ListItem

alias Sanbase.Clickhouse.{
  EthTransfers,
  DailyActiveAddresses,
  EthDailyActiveAddresses,
  Erc20DailyActiveAddresses,
  Erc20Transfers,
  MarkExchanges
}

alias Sanbase.{
  Repo,
  ClickhouseRepo,
  FileStore,
  DateTimeUtils,
  ApplicationUtils,
  Parallel,
  MandrillApi,
  Price
}

alias Sanbase.InternalServices.{
  Ethauth,
  Parity
}

alias Sanbase.ExternalServices.Coinmarketcap.{
  WebApi,
  PricePoint,
  Scraper,
  TickerFetcher,
  Ticker
}

alias Sanbase.TechIndicators

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
  UserResolver,
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
  InsightResolver,
  ClickhouseResolver
}

alias SanbaseWeb.Graphql.Cache
alias SanbaseWeb.Graphql.Helpers.Utils, as: GraphUtils
alias Sanbase.Prices.Store, as: PricesStore
alias Sanbase.Prices.Utils, as: PricesUtils

alias Sanbase.SocialData

alias Sanbase.Signal.{UserTrigger, Trigger, Scheduler}

alias Sanbase.Signal.Trigger.{
  DailyActiveAddressesSettings,
  PricePercentChangeSettings,
  PriceVolumeDifferenceTriggerSettings,
  TrendingWordsTriggerSettings
}

alias Sanbase.Billing.{
  Product,
  Plan,
  Subscription
}

now = fn -> Timex.now() end
days_ago = fn days -> Timex.shift(Timex.now(), days: -days) end

run_test = fn func ->
  Repo.transaction(fn ->
    func.()
    |> Repo.rollback()
  end)
  |> elem(1)
end
