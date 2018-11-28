import React, { Component } from 'react'
import { loadState } from './utils/localStorage'

if (process.env.NODE_ENV === 'production') {
  const loadedState = loadState()
  const user = loadedState ? loadedState.data : {}
  window.Intercom('boot', {
    app_id: 'cyjjko9u',
    email: user.email,
    name: user.username
  })
}

const withIntercom = (WrappedComponent, options = {}) => {
  const updateIntercom = () => {
    if (process.env.NODE_ENV === 'production') {
      window.Intercom('update')
    }
  }

  const HOC = class extends Component {
    componentDidMount () {
      updateIntercom()
    }

    componentWillReceiveProps (nextProps) {
      const currentPage = this.props.location.pathname
      const nextPage = nextProps.location.pathname

      if (currentPage !== nextPage) {
        updateIntercom()
      }
    }

    render () {
      return <WrappedComponent {...this.props} />
    }
  }

  return HOC
}

export default withIntercom
