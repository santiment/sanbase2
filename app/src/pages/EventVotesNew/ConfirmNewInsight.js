import React from 'react'
import Raven from 'raven-js'
import axios from 'axios'
import { compose, withState } from 'recompose'
import { connect } from 'react-redux'
import { Button } from 'semantic-ui-react'
import { withRouter } from 'react-router-dom'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import Post from './../../components/Post'
import ErrorBoundary from './../../ErrorBoundary'

const createPostGQL = gql`
  mutation createPost($link: String!, $title: String!) {
    createPost(
      link: $link,
      title: $title
    ) {
      id
    }
  }
`

const ConfirmPost = ({
  history,
  post,
  createPost,
  user,
  isPending,
  onPending
}) => {
  return (
    <ErrorBoundary>
      <div className='event-posts-new-step'>
        <Post
          votePost={() => {}}
          unvotePost={() => {}}
          user={user} {...post} />
        <div className='event-posts-new-step-control'>
          <Button
            positive
            disabled={isPending}
            onClick={() => {
              onPending(true)
              createPost({
                variables: {title: post.title, link: post.link}
              })
              .then(data => {
                if (process.env.NODE_ENV === 'production') {
                  try {
                    axios({
                      method: 'post',
                      url: 'https://us-central1-cryptofolio-15d92.cloudfunctions.net/alerts',
                      headers: {
                        'authorization': ''
                      },
                      data: {
                        title: post.title,
                        link: post.link,
                        user: user.id
                      }
                    })
                  } catch (error) {
                    Raven.captureException('Alert about new insight ' + JSON.stringify(error))
                  }
                }
                history.push('/insights', {
                  postCreated: true,
                  ...data
                })
              })
              .catch(error => {
                Raven.captureException('User try to confirm new insight. ' + JSON.stringify(error))
              })
            }}>
            {isPending ? 'Waiting' : 'Click && Confirm'}
          </Button>
        </div>
      </div>
    </ErrorBoundary>
  )
}

const mapStateToProps = state => {
  return {
    user: state.user.data
  }
}

const enhance = compose(
  withRouter,
  connect(
    mapStateToProps
  ),
  withState('isPending', 'onPending', false),
  graphql(createPostGQL, {
    name: 'createPost'
  })
)

export default enhance(ConfirmPost)
