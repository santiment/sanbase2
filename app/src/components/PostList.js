import React from 'react'
import { createSkeletonProvider } from '@trainline/react-skeletor'
import Post from './Post.js'
import './PostList.css'

const PostList = ({
  posts = {},
  userId = null,
  balance = null,
  loading = true,
  isError = false,
  isEmpty = true,
  votePost,
  unvotePost,
  deletePost,
  publishPost,
  gotoInsight
}) => (
  <div className='event-posts-list'>
    {Object.keys(posts).map((key, index) => (
      <Post
        showStatus={!!userId}
        index={index + 1}
        key={index}
        balance={balance}
        votePost={votePost}
        unvotePost={unvotePost}
        deletePost={deletePost}
        publishPost={publishPost}
        gotoInsight={gotoInsight}
        {...posts[key]} />
    ))}
  </div>
)

export default createSkeletonProvider(
  {
    posts: [{
      title: '_____',
      link: 'https://sanbase.net',
      createdAt: new Date(),
      user: {
        username: ''
      }
    }, {
      title: '_____',
      link: 'https://sanbase.net',
      createdAt: new Date(),
      user: {
        username: ''
      }
    }]
  },
  ({ posts }) => posts.length === 0,
  () => ({
    backgroundColor: '#bdc3c7',
    color: '#bdc3c7'
  })
)(PostList)
