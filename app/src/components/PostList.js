import React from 'react'
import Post from './Post.js'
import './PostsList.css'

const PostsList = ({posts}) => {
  return (
    <div className='event-posts-list'>
      {Object.keys(posts).map((postKey, index) => (
        <Post
          index={index + 1}
          key={index}
          {...posts[postKey]} />
      ))}
      <hr />
      Counts: {Object.keys(posts).length}
    </div>
  )
}

export default PostsList
