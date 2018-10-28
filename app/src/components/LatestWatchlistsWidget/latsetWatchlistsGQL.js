import gql from 'graphql-tag'

export const latsetWatchlistsGQL = gql`
  query fetchAllPublicUserLists {
    fetchAllPublicUserLists {
      id
      name
      insertedAt
      listItems {
        project {
          name
        }
      }
      user {
        id
        username
      }
    }
  }
`
