import gql from 'graphql-tag'

const allProjectsGQL = gql`{
  allProjects {
    name
    rank
    description
    ticker
    marketSegment
    priceUsd
    percentChange24h
    volumeUsd
    volumeChange24h
    ethSpent
    averageDevActivity
    marketcapUsd
    ethBalance
    btcBalance
    usdBalance
    priceToBookRatio
    ethAddresses {
      address
    }
    twitterData {
      followersCount
    }
    signals {
      name
      description
    }
  }
}`

export default allProjectsGQL
