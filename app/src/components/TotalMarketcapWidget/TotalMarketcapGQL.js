import gql from 'graphql-tag'

export const totalMarketcapGQL = gql`
  query historyPrice($from: DateTime!) {
    historyPrice(from: $from, slug: "TOTAL_MARKET", interval: "1d") {
      marketcap
      volume
      datetime
    }
  }
`

export const projectsGroupStats = gql`
  query projectsGroupStats(
    $from: DateTime!
    $slugs: [String]!
    $to: DateTime!
  ) {
    projectsGroupStats(from: $from, to: $to, slugs: $slugs) {
      marketcap
      volume
    }
  }
`
