alias Sanbase.{
  Project,
  ProjectEthAddress
}

alias Sanbase.Model.{
  Infrastructure,
  MarketSegment,
  LatestCoinmarketcapData,
  ModelUtils,
  Currency,
  Ico,
  IcoCurrency
}

alias Sanbase.Accounts.{
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

alias Sanbase.Transfers.{
  EthTransfers,
  Erc20Transfers,
  BtcTransfers
}

alias Sanbase.{
  Repo,
  ClickhouseRepo,
  FileStore,
  DateTimeUtils,
  ApplicationUtils,
  Parallel,
  Price
}

alias Sanbase.InternalServices.{
  Ethauth,
  EthNode
}

alias Sanbase.ExternalServices.Coinmarketcap.{
  WebApi,
  PricePoint,
  Scraper,
  TickerFetcher,
  Ticker
}

alias Sanbase.ExternalServices.Etherscan.Requests, as: EtherscanRequests
alias Sanbase.ExternalServices.Etherscan.Scraper, as: EtherscanScraper
alias Sanbase.ExternalServices.ProjectInfo

alias Sanbase.Discourse.Api, as: DiscourseApi
alias Sanbase.Discourse.Config, as: DiscourseConfig

alias Sanbase.Messaging.Insight, as: NotificationsInsight
alias Sanbase.Messaging.Discord

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
  EtherbiResolver,
  FileResolver,
  GithubResolver,
  IcoResolver,
  MarketSegmentResolver,
  PostResolver,
  PriceResolver,
  ProjectBalanceResolver,
  ProjectResolver,
  ProjectTransfersResolver,
  TwitterResolver,
  UserListResolver,
  InsightResolver,
  ClickhouseResolver
}

alias SanbaseWeb.Graphql.Cache
alias SanbaseWeb.Graphql.Helpers.Utils, as: GraphUtils
alias Sanbase.Prices.Utils, as: PricesUtils

alias Sanbase.SocialData

alias Sanbase.Alert.{UserTrigger, Trigger, Scheduler}

alias Sanbase.Billing.{
  Product,
  Plan,
  Subscription
}

now = fn -> Timex.now() end
days_ago = fn days -> Timex.shift(Timex.now(), days: -days) end

run_db_test = fn func ->
  Repo.transaction(fn ->
    func.()
    |> Repo.rollback()
  end)
  |> elem(1)
end
