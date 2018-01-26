import React, { Component } from 'react'
import { Route, Redirect } from 'react-router-dom'
import { connect } from 'react-redux'
import Panel from './../../components/Panel'
import PostsNewHeader from './EventVotesNewHeader'
import ConfirmPost from './ConfirmNewInsight'
import CreateLink from './CreateLink'
import CreateTitle from './CreateTitle'
import './EventVotesNew.css'

class EventVotesNew extends Component {
  state = { // eslint-disable-line
    title: '',
    link: '',
    votes: 0,
    author: this.props.username,
    created: new Date()
  }

  changePost = (post, nextStepURL = '') => { // eslint-disable-line
    this.setState({...post}, () => {
      this.props.history.push(`/events/votes/new/${nextStepURL}`)
    })
  }

  savePost = post => { // eslint-disable-line
    console.log('save the post', post)
  }

  render () {
    if (!this.state.link &&
      this.props.history.location.pathname !== '/events/votes/new') {
      return (
        <Redirect to={{
          pathname: '/events/votes/new'
        }} />
      )
    }
    const { addPost } = this.props
    const paths = this.props.history.location.pathname.split('/')
    const last = paths[paths.length - 1]
    return (
      <div className='page event-posts-new'>
        <h2>Post new insight</h2>
        <Panel>
          <PostsNewHeader location={last} />
          <hr />
          <Route
            exact
            path='/events/votes/new'
            render={() => (
              <CreateLink
                changePost={this.changePost}
                post={{...this.state}} />
            )} />
          <Route
            exact
            path='/events/votes/new/title'
            render={() => (
              <CreateTitle
                changePost={this.changePost}
                post={{...this.state}} />
            )} />
          <Route
            exact
            path='/events/votes/new/confirm'
            render={() => (
              <ConfirmPost
                addPost={addPost}
                savePost={this.savePost}
                post={{...this.state}} />
            )} />
        </Panel>
      </div>
    )
  }
}

const mapStateToProps = state => {
  return {
    isLogin: state.user.token,
    username: state.user.data.username
  }
}

const mapDispatchToProps = dispatch => {
  return {
    addPost: post => {
      console.log('add post')
      dispatch({
        type: 'ADD_EVENT_POST',
        payload: {
          post
        }
      })
    }
  }
}

export default connect(
  mapStateToProps,
  mapDispatchToProps
)(EventVotesNew)
