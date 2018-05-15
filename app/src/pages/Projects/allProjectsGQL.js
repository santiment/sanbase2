import gql from 'graphql-tag'

const generalData = gql`
  fragment generalData on Project {
    id
    name
    description
    ticker
    coinmarketcapId
  }
`

const ethereumData = gql`
  fragment ethereumData on Project {
    ethAddresses {
      address
    }
  }
`

const project = gql`
  fragment project on Project {
    rank
    marketSegment
    priceUsd
    percentChange24h
    volumeUsd
    volumeChange24h
    ethSpent
    averageDevActivity
    averageDailyActiveAddresses
    marketcapUsd
    ethBalance
    btcBalance
    usdBalance
    priceToBookRatio
    twitterData {
      followersCount
    }
    signals {
      name
      description
    }
  }
`

export const allProjectsGQL = gql`
  query allProjects {
    allProjects {
      ...generalData
      ...project
    }
  }
  ${generalData}
  ${project}
`

export const allProjectsForSearchGQL = gql`
  query allProjects {
    allProjects {
      ...generalData
    }
  }
  ${generalData}
`

export const allErc20ProjectsGQL = gql`
  query allErc20Projects {
    allErc20Projects {
      ...generalData
      ...project
      ...ethereumData
    }
  }
  ${generalData}
  ${project}
  ${ethereumData}
`

export const currenciesGQL = gql`
  query allCurrencyProjects {
    allCurrencyProjects {
      ...generalData
      ...project
    }
  }
  ${generalData}
  ${project}
`

export const allErc20ShortProjectsGQL = gql`
  query allErc20Projects {
    allErc20Projects {
      ...generalData
      ...ethereumData
      rank
      ethSpent
      coinmarketcapId
      marketcapUsd
      fundsRaisedIcos {
        amount
        currencyCode
      }
    }
  }
  ${generalData}
  ${ethereumData}
`

export const allShortProjectsGQL = gql`{
  allProjects {
    id
    name
    rank
    ethSpent
    coinmarketcapId
    marketcapUsd
    fundsRaisedIcos {
      amount
      currencyCode
    }
    ethAddresses {
      address
    }
  }
}`

export const allMarketSegmentsGQL = gql`{
  allMarketSegments
}`

export default allProjectsGQL
