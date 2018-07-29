import React from 'react'
import { storiesOf } from '@storybook/react'
import { BrowserRouter as Router } from 'react-router-dom'
import Post from './../src/components/Post'
import PostList from './../src/components/PostList'

const posts = [{
    id: 1,
    title: 'Ripple pump!',
    link: 'https://medium.com',
    user: {
      id: 23,
      username: 'Yura Z.'
    },
    state: 'approved',
    votes: 25,
    createdAt: new Date()
  }, {
    id: 2,
    title: 'Btc pump!',
    link: 'https://medium.com',
    user: {
      id: 23,
      username: 'Yura Z.'
    },
    state: null,
    createdAt: new Date()
  }, {
    id: 3,
    title: 'Eth pump!',
    link: 'https://medium.com',
    user: {
      id: 23,
      username: 'Anka Z.'
    },
    state: 'declined',
    moderationComment: 'Any reason of declined',
    votes: 95,
    author: 'jcasdfiu',
    createdAt: new Date()
  }, {
    id: 4,
    title: 'Gcoin pump!',
    link: 'https://medium.com',
    user: {
      id: 13
    },
    votes: 15,
    author: 'jcasdfiu',
    createdAt: new Date()
  }
]


storiesOf('Insights', module)
  .add('Post', () => (
    <Router>
      <div style={{ margin: 20 }}>
        Post component in Insights page
        <hr />
        <Post {...posts[0]} />
      </div>
    </Router>
  ))
  .add('Posts List', () => (
    <Router>
      <div style={{ margin: 20 }}>
        <PostList posts={posts} />
      </div>
    </Router>
  ))
  .add("User's list of insights", () => (
    <Router>
      <div style={{ margin: 20 }}>
        <PostList userId={23} posts={posts} />
      </div>
    </Router>
  ))
