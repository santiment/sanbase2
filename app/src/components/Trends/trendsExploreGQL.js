import gql from 'graphql-tag'

// TODO: from and to parameters
export const trendsExploreGQL = gql`
  query topicSearch($searchText: String!) {
    topicSearch(
      sources: [TELEGRAM, PROFESSIONAL_TRADERS_CHAT, REDDIT]
      searchText: $searchText
      from: "2018-08-01T12:00:00Z"
      to: "2018-08-15T12:00:00Z"
      interval: "6h"
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
