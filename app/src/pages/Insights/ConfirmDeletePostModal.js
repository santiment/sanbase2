import React, { Fragment } from 'react'
import Raven from 'raven-js'
import { Button, Modal } from 'semantic-ui-react'
import {
  compose,
  withState
} from 'recompose'
import { graphql } from 'react-apollo'
import { allInsightsPublicGQL } from './currentPollGQL'
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
      style={{
        marginTop: '35% !important',
        margin: 'auto'
      }}
      dimmer={'blurring'}
      onClose={toggleForm} closeIcon>
      {isSuccess
        ? <Modal.Content>
          <p>Post was deleted.</p>
        </Modal.Content>
        : <Fragment>
          <Modal.Content>
            <p>Do you want to delete this post?</p>
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
                    const data = proxy.readQuery({ query: allInsightsPublicGQL })
                    const newPosts = [...data.allInsights]
                    const postIndex = newPosts.findIndex(post => post.id === deletePost.id)
                    delete newPosts[postIndex]
                    data.allInsights = [
                      ...newPosts.slice(0, postIndex),
                      ...newPosts.slice(postIndex + 1)]
                    proxy.writeQuery({ query: allInsightsPublicGQL, data })
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
