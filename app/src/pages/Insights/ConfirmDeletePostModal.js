import React, { Fragment } from 'react'
import Raven from 'raven-js'
import { Button, Modal } from 'semantic-ui-react'
import {
  compose,
  withState
} from 'recompose'
import { graphql } from 'react-apollo'
import currentPollGQL from './currentPollGQL'
import gql from 'graphql-tag'

const ConfirmDeletePostModal = ({
  deletePostId,
  toggleForm,
  // internal props
  deletePost,
  onSuccess,
  onError,
  onPending,
  isSuccess = false,
  isError = false,
  isPending = false
}) => {
  return (
    <Modal
      defaultOpen
      dimmer={'blurring'}
      onClose={toggleForm} closeIcon>
      {isSuccess
        ? <Modal.Content>
          <p>Post (id: {deletePostId}) was deleted.</p>
        </Modal.Content>
        : <Fragment>
          <Modal.Content>
            <p>Do you want to delete this post? (id: {deletePostId})</p>
          </Modal.Content>
          <Modal.Actions>
            <Button
              basic
              onClick={toggleForm}
            >
              Cancel
            </Button>
            <Button
              negative
              onClick={() => {
                onPending(true)
                deletePost({
                  variables: {id: parseInt(deletePostId, 10)},
                  optimisticResponse: {
                    __typename: 'Mutation',
                    deletePost: {
                      __typename: 'Post',
                      id: deletePostId
                    }
                  },
                  update: (proxy, { data: { deletePost } }) => {
                    const data = proxy.readQuery({ query: currentPollGQL })
                    const newPosts = [...data.currentPoll.posts]
                    const postIndex = newPosts.findIndex(post => post.id === deletePost.id)
                    delete newPosts[postIndex]
                    data.currentPoll.posts = [
                      ...newPosts.slice(0, postIndex),
                      ...newPosts.slice(postIndex + 1)]
                    proxy.writeQuery({ query: currentPollGQL, data })
                  }
                })
                .then(data => {
                  onSuccess(true)
                  onPending(false)
                })
                .catch(e => {
                  Raven.captureException(e)
                  onError(true)
                  onPending(false)
                })
              }}
            >
              {isPending ? 'Waiting...' : 'Delete'}
            </Button>
          </Modal.Actions>
        </Fragment>
      }
    </Modal>
  )
}

const deletePostGQL = gql`
  mutation deletePost($id: ID!) {
    deletePost(id: $id) {
      id
    }
  }
`

const enhance = compose(
  withState('isPending', 'onPending', false),
  withState('isError', 'onError', false),
  withState('isSuccess', 'onSuccess', false),
  graphql(deletePostGQL, {
    name: 'deletePost'
  })
)

export default enhance(ConfirmDeletePostModal)
