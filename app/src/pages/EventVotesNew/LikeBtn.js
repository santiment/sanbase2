import React from 'react'
import { Icon } from 'semantic-ui-react'
import './LikeBtn.css'

const Like = ({
  votes,
  onLike,
  liked = false
}) => (
  <div
    onClick={onLike}
    className='like-btn'>
    {liked
      ? <Icon name='heart' />
      : <Icon name='empty heart' />}
    {votes}
  </div>
)

export default Like
