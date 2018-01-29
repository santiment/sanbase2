import React from 'react'
import Post from './Post.js'
import './PostsList.css'

const PostsList = ({
  posts = [],
  loading = true,
  isError = false,
  isEmpty = true
}) => {
  if (loading) {
    return (<div>Loading...</div>)
  }
  return (
    <div className='event-posts-list'>
      {Object.keys(posts).map((postKey, index) => (
        <Post
          index={index + 1}
          key={index}
          {...posts[postKey]} />
      ))}
    </div>
  )
}

export default PostsList
