import React from 'react'
import CreateInsight from './CreateInsight'
import { withState } from 'recompose'
import { Button } from 'semantic-ui-react'

const CreateBody = ({changePost, post, postBody = null, setPostBody}) => (
  <div style={{padding: '0 20px 20px 20px'}}>
    <CreateInsight initValue={post.text} changePost={raw => {
      setPostBody(raw)
    }} />
    <div className='event-posts-step-control event-posts-step-control_right'>
      <Button
        disabled={!postBody}
        positive={!!postBody}
        onClick={() => {
          const newPost = {
            ...post,
            text: postBody
          }
          changePost(newPost, 'title')
        }}>
        Next
      </Button>
    </div>
  </div>
)

export default withState('postBody', 'setPostBody', null)(CreateBody)
