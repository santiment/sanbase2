import React from 'react'
import Raven from 'raven-js'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import { Button } from 'semantic-ui-react'
import { withRouter } from 'react-router-dom'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import Post from './../../components/Post'

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
  user
}) => {
  return (
    <div className='event-posts-new-step'>
      <Post
        votePost={() => {}}
        unvotePost={() => {}}
        user={user} {...post} />
      <div className='event-posts-new-step-control'>
        <Button
          positive
          onClick={() => createPost({
            variables: {title: post.title, link: post.link}
          }).then(data =>
            history.push('/events/votes', {
              postCreated: true,
              ...data
            }))
            .catch(error => Raven.captureException(error))}>
          Click && Confirm
        </Button>
      </div>
    </div>
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
  graphql(createPostGQL, {
    name: 'createPost',
    options: { fetchPolicy: 'network-only' }
  })
)

export default enhance(ConfirmPost)
