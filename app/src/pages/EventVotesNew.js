import React, { Component } from 'react'
import { Form, FormField } from 'react-form'
import { Route } from 'react-router-dom'
import cx from 'classnames'
import {
  Input,
  Button,
  Message
} from 'semantic-ui-react'
import Panel from './../components/Panel'
import Post from './../components/Post'
import './EventVotesNew.css'

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

const ReactFormInput = FormField(({fieldApi, ...rest}) => {
  const { setValue, setTouched, getValue } = fieldApi
  return (<Input
    value={getValue() || ''}
    onChange={e => setValue(e.target.value)}
    onBlur={e => {
      if (e.target.value && e.target.value.length > 0) {
        setTouched()
      }
    }}
    {...rest}
  />)
})

const errorValidator = values => {
  return {
    link: !values.link ||
      !values.link.match(/(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9]\.[^\s]{2,})/)
        ? 'Input must contain a valid URL' : null
  }
}

const successValidator = values => {
  return {
    link: values.link &&
      values.link.match(/(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9]\.[^\s]{2,})/)
        ? 'Thank you for entering link' : null
  }
}

const isError = formApi => (
  !!formApi.getValue().link &&
    formApi.getValue().link.length > 2 &&
    formApi.getTouched().link &&
    !!formApi.getError().link
)

const CreateLink = ({history, changePost}) => {
  return (
    <Form
      validateError={errorValidator}
      validateSuccess={successValidator}
      onSubmit={values => {
        console.log('check')
        changePost(values, 'title')
      }}>
      {formApi => (<form
        className='event-posts-new-step'
        onSubmit={formApi.submitForm}
        autoComplete='off'>
        <label>Link</label>
        <ReactFormInput
          fluid
          field='link'
          error={isError(formApi)}
          placeholder='Paster a URL (e.g. https://twitter/insight)' />
        {isError(formApi) &&
          <Message negative>
            {formApi.getError().link}
          </Message>}
        <div className='event-posts-new-step-control'>
          <Button
            disabled={!!formApi.getError().link}
            positive={!!formApi.getSuccess().link}
            type='submit'>
            Next
          </Button>
        </div>
      </form>)}
    </Form>
  )
}

const CreateTitle = ({changePost}) => {
  return (
    <Form onSubmit={values => {
      changePost(values, 'confirm')
    }}>
      {formApi => (<form
        className='event-posts-new-step'
        onSubmit={formApi.submitForm}
        autoComplete='off'>
        <label>Title</label>
        <ReactFormInput
          focus
          fluid
          field='title'
          placeholder='Add a title' />
        <div className='event-posts-new-step-control'>
          <Button
            type='submit'>
            Next
          </Button>
        </div>
      </form>)}
    </Form>
  )
}

const ConfirmPost = ({post}) => {
  return (
    <div className='event-posts-new-step'>
      <Panel>
        <Post {...post} />
      </Panel>
      <div className='event-posts-new-step-control'>
        <Button type='submit' disabled>
          Confirm
        </Button>
      </div>
    </div>
  )
}

class EventVotesNew extends Component {
  state = { // eslint-disable-line
    title: 'Ripple pump!',
    link: 'https://medium.com',
    votes: 0,
    author: 'sdfefw',
    created: new Date()
  }

  changePost = (post, nextStepURL = '') => { // eslint-disable-line
    this.setState({...post}, () => {
      this.props.history.push(`/events/votes/new/${nextStepURL}`)
    })
  }

  render () {
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
              <ConfirmPost post={{...this.state}} />
            )} />
        </Panel>
        <hr />
        <Panel>
          <Post {...this.state} />
        </Panel>
      </div>
    )
  }
}

export default EventVotesNew
