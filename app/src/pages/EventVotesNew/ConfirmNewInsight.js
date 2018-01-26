import React from 'react'
import { Button } from 'semantic-ui-react'
import { withRouter } from 'react-router-dom'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import Panel from './../../components/Panel'
import Post from './../../components/Post'

const createPostGQL = gql`
  mutation createPost($link: String!, $title: String!) {
    createPost(
      link: $link,
      title: $title
    ) {
      id
    }
}`

const ConfirmPost = ({
  history,
  post,
  createPost
}) => {
  return (
    <div className='event-posts-new-step'>
      <Panel>
        <Post {...post} />
      </Panel>
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
            .catch(error =>
            console.log(error))}>
          Click && Confirm
        </Button>
      </div>
    </div>
  )
}

export default withRouter(graphql(createPostGQL, {
  name: 'createPost',
  options: { fetchPolicy: 'network-only' }
})(ConfirmPost))
