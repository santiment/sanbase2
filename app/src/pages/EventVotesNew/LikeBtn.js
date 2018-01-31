import React from 'react'
import { Icon } from 'semantic-ui-react'
import { formatBTC } from './../../utils/formatting'
import './LikeBtn.css'

const Like = ({
  votes = 0,
  onLike,
  liked = false
}) => (
  <div
    onClick={onLike}
    className='like-btn'>
    {liked
      ? <Icon name='heart' />
      : <Icon name='empty heart' />}
    {formatBTC(parseFloat(votes))}
  </div>
)

export default Like
