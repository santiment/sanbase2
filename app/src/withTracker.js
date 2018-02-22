import React, { Component } from 'react'
import GoogleAnalytics from 'react-ga'

if (process.env.NODE_ENV === 'production') {
  GoogleAnalytics.initialize('UA-100571693-2')
} else {
  GoogleAnalytics.initialize('foo', { testMode: true })
}

const withTracker = (WrappedComponent, options = {}) => {
  const trackPage = page => {
    if (process.env.NODE_ENV === 'production') {
      GoogleAnalytics.set({
        page,
        ...options
      })
      GoogleAnalytics.pageview(page)
    }
  }

  const HOC = class extends Component {
    componentDidMount () {
      const page = this.props.location.pathname
      trackPage(page)
    }

    componentWillReceiveProps (nextProps) {
      const currentPage = this.props.location.pathname
      const nextPage = nextProps.location.pathname

      if (currentPage !== nextPage) {
        trackPage(nextPage)
      }
    }

    render () {
      return <WrappedComponent {...this.props} />
    }
  }

  return HOC
}

export default withTracker
