import gql from 'graphql-tag'

export const projectBySlugGQL = gql`
  query projectBySlugGQL(
    $slug: String!
    $from: DateTime
    $fromOverTime: DateTime
    $to: DateTime
    $interval: String!
  ) {
    projectBySlug(slug: $slug) {
      id
      name
      slug
      ticker
      description
      websiteLink
      email
      blogLink
      telegramLink
      facebookLink
      githubLink
      redditLink
      twitterLink
      whitepaperLink
      slackLink
      infrastructure
      btcBalance
      projectTransparency
      projectTransparencyDescription
      projectTransparencyStatus
      tokenAddress
      fundsRaisedIcos {
        amount
        currencyCode
      }
      initialIco {
        id
        tokenUsdIcoPrice
      }
      icoPrice
      roiUsd
      priceUsd
      priceBtc
      volumeUsd
      ethBalance
      ethAddresses {
        balance
        address
      }

      ethTopTransactions(from: $from, to: $to) {
        datetime
        trxValue
        trxHash
        fromAddress {
          address
          isExchange
        }
        toAddress {
          address
          isExchange
        }
      }

      tokenTopTransactions(from: $from, to: $to) {
        datetime
        trxValue
        trxHash
        fromAddress {
          address
          isExchange
        }
        toAddress {
          address
          isExchange
        }
      }

      ethSpentOverTime(from: $fromOverTime, to: $to, interval: $interval) {
        datetime
        ethSpent
      }
      ethSpent
      marketcapUsd
      tokenDecimals
      rank
      totalSupply
      percentChange24h
    }
  }
`

export const historyPriceGQL = gql`
  query historyPriceGQL(
    $slug: String
    $from: DateTime
    $to: DateTime
    $interval: String
  ) {
    historyPrice(slug: $slug, from: $from, to: $to, interval: $interval) {
      priceBtc
      priceUsd
      volume
      datetime
      marketcap
    }
  }
`
