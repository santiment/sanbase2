import React, { Component } from 'react'
import Raven from 'raven-js'
import { Message } from 'semantic-ui-react'

class ErrorBoundary extends Component {
  state = {
    error: null
  }

  componentDidCatch (error, errorInfo) {
    this.setState({ error })
    Raven.captureException(error, { extra: errorInfo })
  }

  render () {
    if (this.state.error) {
      return (
        <div className='page wrapper'>
          <Message
            size='massive'
            negative
            onClick={() => Raven.lastEventId() && Raven.showReportDialog()}
          >
            <Message.Header>
              We're sorry — something's gone wrong.
            </Message.Header>
            {Raven.lastEventId() && <p>Error ID: {Raven.lastEventId()}</p>}
            <p>Our team has been notified, but click here fill out a report.</p>
          </Message>
        </div>
      )
    } else {
      return this.props.children
    }
  }
}

export default ErrorBoundary
