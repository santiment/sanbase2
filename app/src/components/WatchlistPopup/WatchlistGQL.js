import gql from 'graphql-tag'

export const WatchlistGQL = gql`
  query fetchUserLists {
    fetchUserLists {
      id
      color
      isPublic
      name
      listItems {
        project {
          id
          slug
        }
      }
      insertedAt
      updatedAt
    }
  }
`

export const publicWatchlistGQL = gql`
  query fetchAllPublicUserLists {
    fetchAllPublicUserLists {
      id
      color
      isPublic
      name
      listItems {
        project {
          id
          slug
        }
      }
      insertedAt
      updatedAt
    }
  }
`
