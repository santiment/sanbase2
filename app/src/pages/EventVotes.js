import React from 'react'
import { NavLink } from 'react-router-dom'
import Panel from './../components/Panel'
import PostsList from './../components/PostsList'
import { Icon } from 'semantic-ui-react'
import './EventVotes.css'

const posts = {
  'asffe2f2f': {
    title: 'Ripple pump!',
    link: 'https://medium.com',
    votes: 25,
    author: 'sdfefw',
    liked: true,
    created: new Date()
  },
  'a23429r3f': {
    title: 'Eth pump!',
    link: 'https://medium.com',
    votes: 95,
    author: 'jcasdfiu',
    created: new Date()
  },
  'asf2342ff': {
    title: 'Gcoin pump!',
    link: 'https://medium.com',
    votes: 15,
    liked: true,
    author: 'jcasdfiu',
    created: new Date()
  }
}

const EventVotes = () => {
  return (
    <div className='page event-votes'>
      <Panel>
        <div className='event-votes-header'>
          <span>Insights</span>
          <NavLink
            className='event-votes-navigation__add-link'
            to={'/events/votes/new'}>
            <Icon name='als' /> Add new insight
          </NavLink>
          <div className='event-votes-navigation'>
            <NavLink
              className='event-votes-navigation__link'
              activeClassName='event-votes-navigation__link--active'
              exact
              to={'/events/votes'}>
              POPULAR
            </NavLink>
            <NavLink
              className='event-votes-navigation__link'
              activeClassName='event-votes-navigation__link--active'
              exact
              to={'/events/votes/newest'}>
              NEWEST
            </NavLink>
          </div>
        </div>
        <PostsList posts={posts} />
      </Panel>
    </div>
  )
}

export default EventVotes
