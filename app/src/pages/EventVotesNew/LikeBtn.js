import React from 'react'
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
      ? <i className='fa fa-heart' />
      : <i className='fa fal fa-heart-o' />}
    {formatBTC(votes)}
  </div>
)

export default Like
