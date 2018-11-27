import gql from 'graphql-tag'

const generalData = gql`
  fragment generalData on Project {
    id
    name
    slug
    description
    ticker
    coinmarketcapId
  }
`

const ethereumData = gql`
  fragment ethereumData on Project {
    fundsRaisedUsdIcoEndPrice
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

export const projectBySlugGQL = gql`
  query projectBySlugGQL($slug: String!) {
    projectBySlug(slug: $slug) {
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
`

export const allShortProjectsGQL = gql`
  {
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
  }
`

export const allMarketSegmentsGQL = gql`
  {
    allMarketSegments {
      name
      count
    }
  }
`

export const erc20MarketSegmentsGQL = gql`
  {
    erc20MarketSegments {
      name
      count
    }
  }
`

export const currenciesMarketSegmentsGQL = gql`
  {
    currenciesMarketSegments {
      name
      count
    }
  }
`

export default allProjectsGQL
