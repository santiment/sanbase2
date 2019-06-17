# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :ex_admin,
  repo: Sanbase.Repo,
  # MyProject.Web for phoenix >= 1.3.0-rc
  module: SanbaseWeb,
  modules: [
    Sanbase.ExAdmin.Dashboard,
    Sanbase.ExAdmin.Statistics,
    Sanbase.ExAdmin.Model.Project,
    Sanbase.ExAdmin.Model.ProjectBtcAddress,
    Sanbase.ExAdmin.Model.ProjectEthAddress,
    Sanbase.ExAdmin.Model.Ico,
    Sanbase.ExAdmin.Model.ExchangeAddress,
    Sanbase.ExAdmin.Model.Currency,
    Sanbase.ExAdmin.Model.IcoCurrency,
    Sanbase.ExAdmin.Model.Infrastructure,
    Sanbase.ExAdmin.Model.MarketSegment,
    Sanbase.ExAdmin.Model.ProjectTransparencyStatus,
    Sanbase.ExAdmin.Model.LatestCoinmarketcapData,
    Sanbase.ExAdmin.Model.LatestBtcWalletData,
    Sanbase.ExAdmin.Notifications.Type,
    Sanbase.ExAdmin.Notifications.Notification,
    Sanbase.ExAdmin.Auth.User,
    Sanbase.ExAdmin.Auth.EthAccount,
    Sanbase.ExAdmin.Auth.UserApikeyToken,
    Sanbase.ExAdmin.Auth.UserSettings,
    Sanbase.ExAdmin.Insight.Poll,
    Sanbase.ExAdmin.Insight.Post,
    Sanbase.ExAdmin.UserList,
    Sanbase.ExAdmin.ScheduleRescrapePrice,
    Sanbase.ExAdmin.Signals.HistoricalActivity,
    Sanbase.ExAdmin.Signals.UserTrigger,
    Sanbase.ExAdmin.FeaturedItem,
    Sanbase.ExAdmin.TimelineEvent
  ],
  basic_auth: [
    username: {:system, "ADMIN_BASIC_AUTH_USERNAME"},
    password: {:system, "ADMIN_BASIC_AUTH_PASSWORD"},
    realm: {:system, "ADMIN_BASIC_AUTH_REALM"}
  ]
