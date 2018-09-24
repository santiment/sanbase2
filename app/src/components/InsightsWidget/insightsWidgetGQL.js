import gql from 'graphql-tag'

export const insightsWidgetGQL = gql`
  query allInsights {
    allInsights {
      id
      createdAt
      title
      text
      user {
        id
        username
      }
    }
  }
`
