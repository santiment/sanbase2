import React, { Fragment } from 'react'
import { Popup } from 'semantic-ui-react'
import { formatBTC } from './../../utils/formatting'
import './LikeBtn.css'

const Like = ({ votes = {}, onLike, balance = null, liked = false }) => {
  const { totalSanVotes = 0, totalVotes = 0 } = votes
  return (
    <Fragment>
      {balance > 0 ? (
        <div onClick={onLike} className='like-btn'>
          {`${formatBTC(totalSanVotes)} SAN`}, &nbsp;
          {totalVotes}
          &nbsp;
          {liked ? (
            <i className='fa fa-heart' />
          ) : (
            <i className='fa fal fa-heart-o' />
          )}
        </div>
      ) : (
        <Popup
          basic
          trigger={<i className='fa fal fa-heart-o fa-disabled' />}
          content='You need to have SAN balance before.'
          inverted
          position='bottom left'
        />
      )}
    </Fragment>
  )
}

export default Like
