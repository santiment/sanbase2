# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

config :ex_admin,
  repo: Sanbase.Repo,
  # MyProject.Web for phoenix >= 1.3.0-rc
  module: SanbaseWeb,
  modules: [
    Sanbase.ExAdmin.Dashboard,
    Sanbase.ExAdmin.Statistics,
    Sanbase.ExAdmin.Statistics.UsersWithWatchlist,
    Sanbase.ExAdmin.Statistics.UsersWithMonitoredWatchlist,
    Sanbase.ExAdmin.Statistics.UsersWithDailyNewsletterSubscription,
    Sanbase.ExAdmin.Statistics.UsersWithWeeklyNewsletterSubscription,
    Sanbase.ExAdmin.Model.Project,
    Sanbase.ExAdmin.Kafka.KafkaLabelRecord,
    Sanbase.ExAdmin.Insight.Comment,
    Sanbase.ExAdmin.Model.Currency,
    Sanbase.ExAdmin.Auth.EthAccount,
    Sanbase.ExAdmin.Model.ExchangeAddress,
    Sanbase.ExAdmin.FeaturedItem,
    Sanbase.ExAdmin.Model.Project.GithubOrganization,
    Sanbase.ExAdmin.Signal.HistoricalActivity,
    Sanbase.ExAdmin.Model.Ico,
    Sanbase.ExAdmin.Model.IcoCurrency,
    Sanbase.ExAdmin.Model.Infrastructure,
    Sanbase.ExAdmin.Model.LatestBtcWalletData,
    Sanbase.ExAdmin.Model.LatestCoinmarketcapData,
    Sanbase.ExAdmin.Model.MarketSegment,
    Sanbase.ExAdmin.Notifications.Notification,
    Sanbase.ExAdmin.Billing.Plan,
    Sanbase.ExAdmin.Insight.Post,
    Sanbase.ExAdmin.Insight.PostComment,
    Sanbase.ExAdmin.PriceScrapingProgress,
    Sanbase.ExAdmin.Billing.Product,
    Sanbase.ExAdmin.Model.ProjectBtcAddress,
    Sanbase.ExAdmin.Model.ProjectEthAddress,
    Sanbase.ExAdmin.Model.ProjectMarketSegment,
    Sanbase.ExAdmin.Billing.PromoTrial,
    Sanbase.ExAdmin.ScheduleRescrapePrice,
    Sanbase.ExAdmin.Model.Project.SocialVolumeQuery,
    Sanbase.ExAdmin.Model.Project.SourceSlugMapping,
    Sanbase.ExAdmin.Billing.StripeEvent,
    Sanbase.ExAdmin.Billing.Subscription,
    Sanbase.ExAdmin.TimelineEvent,
    Sanbase.ExAdmin.Notifications.Type,
    Sanbase.ExAdmin.Auth.User,
    Sanbase.ExAdmin.Auth.UserApikeyToken,
    Sanbase.ExAdmin.Auth.UserRole,
    Sanbase.ExAdmin.UserList,
    Sanbase.ExAdmin.Auth.UserSettings,
    Sanbase.ExAdmin.Signal.UserTrigger,
    Sanbase.ExAdmin.PriceMigrationTmp,
    Sanbase.ExAdmin.Exchanges.MarketPairMapping,
    Sanbase.ExAdmin.Billing.SignUpTrial
  ],
  basic_auth: [
    username: {:system, "ADMIN_BASIC_AUTH_USERNAME"},
    password: {:system, "ADMIN_BASIC_AUTH_PASSWORD"},
    realm: {:system, "ADMIN_BASIC_AUTH_REALM"}
  ]
