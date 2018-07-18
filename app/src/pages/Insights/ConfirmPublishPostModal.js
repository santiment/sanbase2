import React, { Fragment } from 'react'
import Raven from 'raven-js'
import { Button, Modal } from 'semantic-ui-react'
import { compose, withState } from 'recompose'
import { graphql } from 'react-apollo'
import { allInsightsGQL } from './currentPollGQL'
import gql from 'graphql-tag'

const ConfirmPublishPostModal = ({
  publishInsightId,
  toggleForm,
  // internal props
  publishInsight,
  onSuccess,
  onError,
  onPending,
  isSuccess = false,
  isError = false,
  isPending = false
}) => {
  return (
    <Modal defaultOpen dimmer={'blurring'} onClose={toggleForm} closeIcon>
      {isSuccess ? (
        <Modal.Content>
          <p>Post was published.</p>
        </Modal.Content>
      ) : (
        <Fragment>
          <Modal.Content>
            <p>Do you want to publish this insight?</p>
          </Modal.Content>
          <Modal.Actions>
            <Button basic onClick={toggleForm}>
              Cancel
            </Button>
            <Button
              color='orange'
              onClick={() => {
                onPending(true)
                publishInsight({
                  variables: { id: parseInt(publishInsightId, 10) },
                  optimisticResponse: {
                    __typename: 'Mutation',
                    publishInsight: {
                      __typename: 'Post',
                      id: publishInsightId
                    }
                  },
                  update: (proxy, { data: { publishInsight } }) => {
                    const data = proxy.readQuery({ query: allInsightsGQL })
                    const newPosts = [...data.allInsights]
                    const postIndex = newPosts.findIndex(
                      post => post.id === publishInsight.id
                    )
                    data.allInsights = [
                      ...newPosts.slice(0, postIndex),
                      {
                        ...newPosts[postIndex],
                        readyState: 'published'
                      },
                      ...newPosts.slice(postIndex + 1)
                    ]
                    proxy.writeQuery({ query: allInsightsGQL, data })
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
              {isPending ? 'Waiting...' : 'Publish'}
            </Button>
          </Modal.Actions>
        </Fragment>
      )}
    </Modal>
  )
}

const publishInsightGQL = gql`
  mutation publishInsight($id: ID!) {
    publishInsight(id: $id) {
      id
    }
  }
`

const enhance = compose(
  withState('isPending', 'onPending', false),
  withState('isError', 'onError', false),
  withState('isSuccess', 'onSuccess', false),
  graphql(publishInsightGQL, {
    name: 'publishInsight'
  })
)

export default enhance(ConfirmPublishPostModal)
