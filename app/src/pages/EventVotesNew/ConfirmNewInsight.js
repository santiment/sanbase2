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
import { allInsightsGQL } from './../Insights/currentPollGQL'
import ErrorBoundary from './../../ErrorBoundary'

const createPostGQL = gql`
  mutation createPost($title: String!, $text: String!, $tags: [String]) {
    createPost(
      title: $title
      text: $text
      tags: $tags
    ) {
      id
      title
      text
      tags {
        name
      }
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
      <div className='event-posts-new-step event-posts-step-confirm'>
        <Post
          votePost={() => {}}
          unvotePost={() => {}}
          gotoInsight={() => {}}
          user={user} {...post} />
        <div className='event-posts-new-step-control'>
          <Button
            positive
            disabled={isPending}
            onClick={() => {
              onPending(true)
              createPost({
                variables: {
                  title: post.title,
                  text: post.text,
                  tags: post.tags.map(tag => {
                    return tag.label
                  })
                },
                optimisticResponse: {
                  __typename: 'Mutation',
                  createPost: {
                    __typename: 'Post',
                    id: 'last',
                    title: post.title,
                    text: post.text,
                    tags: post.tags.map(tag => {
                      return tag.label
                    })
                  }
                },
                update: (proxy, { data: { createPost } }) => {
                  const { id, title, text, tags } = createPost
                  const data = proxy.readQuery({ query: allInsightsGQL })
                  let newPosts = [...data.allInsights]
                  if (id === 'last') {
                    newPosts.push({
                      id,
                      title,
                      tags,
                      text,
                      totalSanVotes: 0,
                      createdAt: new Date(),
                      readyState: 'draft',
                      votedAt: null,
                      state: null,
                      moderationComment: '',
                      user: user,
                      __typename: 'Post'
                    })
                  } else {
                    const postIndex = newPosts.findIndex(post => post.id === 'last')
                    newPosts = [
                      ...newPosts.slice(0, postIndex),
                      ...newPosts.slice(postIndex + 1)]
                    newPosts.push({
                      id,
                      title,
                      tags,
                      text,
                      totalSanVotes: 0,
                      createdAt: new Date(),
                      readyState: 'draft',
                      votedAt: null,
                      state: null,
                      moderationComment: '',
                      user: user,
                      __typename: 'Post'
                    })
                  }
                  data.allInsights = newPosts
                  proxy.writeQuery({ query: allInsightsGQL, data })
                }
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
                history.push('/insights/my', {
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
