import React from 'react'
import cx from 'classnames'

const HeaderLink = ({title, active = false}) => (
  <li
    className={cx({
      'event-posts-new-navigation-link': true,
      'event-posts-new-navigation--active': active
    })}>
    {title}
  </li>
)

const PostsNewHeader = ({location}) => (
  <div className='event-posts-new-navigation'>
    <ol>
      <HeaderLink
        title='1. Link'
        active={location === 'new'} />
      <HeaderLink
        title='2. Title'
        active={location === 'title'} />
      <HeaderLink
        title='3. Confirm'
        active={location === 'confirm'} />
    </ol>
  </div>
)

export default PostsNewHeader
