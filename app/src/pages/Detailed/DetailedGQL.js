import gql from 'graphql-tag'

export const projectBySlugGQL = gql`
  query projectBySlugGQL($slug: String!, $from: DateTime, $fromOverTime: DateTime, $to: DateTime, $interval: String!) {
    projectBySlug(
      slug: $slug,
    ){
      id,
      name,
      ticker,
      description,
      websiteLink,
      email,
      blogLink,
      telegramLink,
      facebookLink,
      githubLink,
      redditLink,
      twitterLink,
      whitepaperLink,
      slackLink,
      infrastructure,
      btcBalance,
      projectTransparency,
      projectTransparencyDescription,
      projectTransparencyStatus,
      tokenAddress,
      fundsRaisedIcos { amount, currencyCode },
      initialIco {
        id
        tokenUsdIcoPrice
      },
      icoPrice,
      roiUsd,
      priceUsd,
      priceBtc,
      volumeUsd,
      ethBalance,
      ethAddresses {
        balance,
        address
      },
      ethTopTransactions(from: $from, to: $to, limit: 10, transactionType: OUT) {
        fromAddress,
        trxValue,
        trxHash,
        toAddress,
        datetime
      },
      ethSpentOverTime(from: $fromOverTime, to: $to, interval: $interval) {
        datetime,
        ethSpent
      },
      ethSpent,
      marketcapUsd,
      tokenDecimals,
      rank,
      totalSupply,
      percentChange24h,
    }
  }
`

export const TwitterHistoryGQL = gql`
  query queryTwitterHistory($ticker:String!, $from: DateTime, $to: DateTime, $interval: String) {
    historyTwitterData(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime
      followersCount
      __typename
    }
  }
`

export const TwitterDataGQL = gql`
  query queryTwitterData($ticker:String!) {
    twitterData(ticker: $ticker) {
      datetime
      followersCount
      twitterName
    }
  }
`

export const HistoryPriceGQL = gql`
  query queryHistoryPrice($ticker: String, $from: DateTime, $to: DateTime, $interval: String) {
    historyPrice(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      priceBtc,
      priceUsd,
      volume,
      datetime,
      marketcap
    }
}`

export const GithubActivityGQL = gql`
  query queryGithubActivity($ticker: String, $from: DateTime, $to: DateTime, $interval: String, $transform: String, $movingAverageIntervalBase: String) {
    githubActivity(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval,
      transform: $transform,
      movingAverageIntervalBase: $movingAverageIntervalBase
    ) {
      datetime,
      activity
    }
}`

export const BurnRateGQL = gql`
  query queryBurnRate($slug: String, $from: DateTime, $to: DateTime, $interval: String) {
    burnRate(
      slug: $slug,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime
      burnRate
      __typename
    }
}`

export const TransactionVolumeGQL = gql`
  query queryTransactionVolume($slug:String, $from: DateTime, $to: DateTime, $interval: String) {
    transactionVolume(
      slug: $slug,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime
      transactionVolume
      __typename
    }
}`

export const ExchangeFundFlowGQL = gql`
  query exchangeFundFlowGQL($slug:String, $from: DateTime, $to: DateTime) {
    exchangeFundFlow(
      slug: $slug,
      from: $from,
      to: $to,
      transactionType: ALL
    ) {
      datetime
      transactionVolume
      address
      __typename
    }
}`

export const EthSpentOverTimeByErc20ProjectsGQL = gql`
  query ethSpentOverTimeByErc20Projects($interval:String, $from: DateTime, $to: DateTime) {
    ethSpentOverTimeByErc20Projects(
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime
      ethSpent
      __typename
    }
}`

export const EmojisSentimentGQL = gql`
  query emojisSentiment($from: DateTime, $to: DateTime, $interval: String) {
    emojisSentiment(
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime
      sentiment
      __typename
    }
}`

export const DailyActiveAddressesGQL = gql`
  query dailyActiveAddresses($slug:String, $from: DateTime, $to: DateTime, $interval: String) {
    dailyActiveAddresses(
      slug: $slug,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      datetime
      activeAddresses
      __typename
    }
}`

export const followedProjectsGQL = gql`
  query followedProjects {
    followedProjects {
        id,
      }
}`

export const FollowProjectGQL = gql`
  mutation followProject($projectId: Int!) {
    followProject(projectId: $projectId) {
      id
    }
}`

export const UnfollowProjectGQL = gql`
  mutation unfollowProject($projectId: Int!) {
    unfollowProject(projectId: $projectId) {
      id
    }
}`

export const AllInsightsByTagGQL = gql`
  query allInsightsByTag($tag:String!) {
    allInsightsByTag(
      tag: $tag
    ) {
      user {
        username
      }
      title
      text
      createdAt
      state
      readyState
      votedAt
      votes {
        totalSanVotes
        totalVotes
      }
      __typename
    }
}`
