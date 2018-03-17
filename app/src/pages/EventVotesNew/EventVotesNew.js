import React, { Component } from 'react'
import { Route, Redirect } from 'react-router-dom'
import { connect } from 'react-redux'
import Panel from './../../components/Panel'
import PostsNewHeader from './EventVotesNewHeader'
import ConfirmPost from './ConfirmNewInsight'
import CreateTitle from './CreateTitle'
import CreateBody from './CreateBody'
import './EventVotesNew.css'

class EventVotesNew extends Component {
  state = { // eslint-disable-line
    title: '',
    link: '',
    text: '',
    votes: 0,
    author: this.props.username,
    created: new Date()
  }

  changePost = (post, nextStepURL = '') => { // eslint-disable-line
    this.setState({...post}, () => {
      this.props.history.push(`/insights/new/${nextStepURL}`)
    })
  }

  savePost = post => { // eslint-disable-line
    console.log('save the post', post)
  }

  render () {
    if (!this.state.text &&
      this.props.history.location.pathname !== '/insights/new') {
      return (
        <Redirect to={{
          pathname: '/insights/new'
        }} />
      )
    }
    const { addPost } = this.props
    const paths = this.props.history.location.pathname.split('/')
    const last = paths[paths.length - 1]
    return (
      <div className='page event-posts-new'>
        <Panel>
          <div className='panel-header'>
            Post new insight
          </div>
          <PostsNewHeader location={last} />
          <Route
            exact
            path='/insights/new'
            render={() => (
              <CreateBody
                changePost={this.changePost}
                post={{...this.state}} />
          )} />
          <Route
            exact
            path='/insights/new/title'
            render={() => (
              <CreateTitle
                changePost={this.changePost}
                post={{...this.state}} />
            )} />
          <Route
            exact
            path='/insights/new/confirm'
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
