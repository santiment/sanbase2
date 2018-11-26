import gql from 'graphql-tag'

export const latestWatchlistsGQL = gql`
  query fetchAllPublicUserLists {
    fetchAllPublicUserLists {
      id
      name
      insertedAt
      listItems {
        project {
          id
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
