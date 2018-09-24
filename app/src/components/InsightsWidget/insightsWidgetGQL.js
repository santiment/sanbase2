import gql from 'graphql-tag'

export const insightsWidgetGQL = gql`
  query allInsights {
    allInsights {
      id
      createdAt
      title
      text
      images {
        imageUrl
      }
      user {
        id
        username
      }
    }
  }
`
