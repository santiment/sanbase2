import gql from 'graphql-tag'

export const updateUserListGQL = gql`
  mutation updateUserList($id: Int!, $isPublic: Boolean) {
    updateUserList(id: $id, isPublic: $isPublic) {
      isPublic
    }
  }
`
export const fetchUserListsGQL = gql`
  query fetchUserLists {
    fetchUserLists {
      id
      isPublic
      user {
        id
      }
    }
  }
`
