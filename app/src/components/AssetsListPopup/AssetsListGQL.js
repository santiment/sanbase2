import gql from 'graphql-tag'

export const AssetsListGQL = gql`
  query fetchUserLists {
    fetchUserLists {
    id
    color
    isPublic
    name
  }
}`
