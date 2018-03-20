import gql from 'graphql-tag'

export const projectBySlugGQL = gql`
  query projectBySlugGQL($slug: String!) {
    projectBySlug(
      slug: $slug,
    ){
      id,
      name,
      ticker,
      description,
      websiteLink,
      facebookLink,
      githubLink,
      redditLink,
      twitterLink,
      whitepaperLink,
      slackLink,
      btcBalance,
      projectTransparency,
      projectTransparencyDescription,
      projectTransparencyStatus,
      tokenAddress,
      fundsRaisedIcos { amount, currencyCode },
      roiUsd,
      priceUsd,
      priceBtc,
      volumeUsd,
      ethBalance,
      ethAddresses {
        balance,
        address
      },
      ethTopTransactions(from: "2018-02-20T00:00:00Z", to: "2018-03-20T00:00:00Z", limit: 10, transactionType: OUT) {
        fromAddress,
        trxValue,
        toAddress,
        datetime
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
  query queryGithubActivity($ticker: String, $from: DateTime, $to: DateTime, $interval: String, $transform: String, $movingAverageInterval: Int) {
    githubActivity(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval,
      transform: $transform,
      movingAverageInterval: $movingAverageInterval
    ) {
      datetime,
      activity
    }
}`

export const BurnRateGQL = gql`
  query queryBurnRate($ticker:String, $from: DateTime, $to: DateTime) {
    burnRate(
      ticker: $ticker,
      from: $from,
      to: $to
    ) {
      datetime
      burnRate
      __typename
    }
}`

export const TransactionVolumeGQL = gql`
  query queryTransactionVolume($ticker:String, $from: DateTime, $to: DateTime) {
    transactionVolume(
      ticker: $ticker,
      from: $from,
      to: $to
    ) {
      datetime
      transactionVolume
      __typename
    }
}`
