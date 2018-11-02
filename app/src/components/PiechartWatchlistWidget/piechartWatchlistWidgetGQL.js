import gql from 'graphql-tag'

export const piechartWatchlistWidgetGQL = gql`
  query projectsGroupStats(
    $from: DateTime!
    $to: DateTime!
    $slugs: [String]!
  ) {
    projectsGroupStats(from: $from, to: $to, slugs: $slugs) {
      marketcap
      marketcapPercent {
        percent
        slug
      }
    }
  }
`
