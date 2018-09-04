import gql from 'graphql-tag'

export const trendsExploreGQL = gql`
  query topicSearch($from: DateTime!, $searchText: String!) {
    topicSearch(
      sources: [TELEGRAM, PROFESSIONAL_TRADERS_CHAT, REDDIT]
      searchText: $searchText
      from: $from
      interval: "1d"
    ) {
      chartsData {
        telegram {
          mentionsCount
          datetime
        }
        professionalTradersChat {
          mentionsCount
          datetime
        }
        reddit {
          mentionsCount
          datetime
        }
      }
    }
  }
`
