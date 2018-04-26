import React, { Component } from 'react'
import { Route, Redirect } from 'react-router-dom'
import { connect } from 'react-redux'
import Panel from './../../components/Panel'
import PostsNewHeader from './EventVotesNewHeader'
import ConfirmPost from './ConfirmNewInsight'
import CreateTitle from './CreateTitle'
import CreateBody from './CreateBody'
import InsightsLayout from './../Insights/InsightsLayout'
import './EventVotesNew.css'

class EventVotesNew extends Component {
  state = { // eslint-disable-line
    title: '',
    link: '',
    text: '',
    votes: 0,
    tags: [],
    author: this.props.username,
    created: new Date()
  }

  changePost = (post, nextStepURL = '') => { // eslint-disable-line
    this.setState({...post}, () => {
      this.props.history.push(`/insights/new/${nextStepURL}`)
    })
  }

  savePost = post => { // eslint-disable-line
    console.log('Save the inisight', post)
  }

  componentDidMount () {
    if (!this.props.isLogin) {
      this.props.history.push('/login')
    }
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
      <InsightsLayout
        sidebar={
          <div style={{marginTop: 16}}>
            <p>
              Use Insights to journal your ideas, as a way to teach yourself, perform research, or share with others.
            </p>
            <p>
              Record your trades or research notes, and learn more about your investing style, track your progress over time, and study trends. You can also share (“publish”) Insights publicly to teach others, build your reputation and educate yourself at the same time! You will be participating in the proper decentralisation of creating, owning and sharing financial information in our society.
            </p>
            <p>
              Plus, you could benefit financially from your skills in “understanding the crypto”.
            </p>
          </div>}
        isLogin={this.state.isLogin}>
        <div className='event-posts-new'>
          <Panel>
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
      </InsightsLayout>
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
