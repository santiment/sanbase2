import React, { Component } from 'react'
import Raven from 'raven-js'
import { Message, Button } from 'semantic-ui-react'

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
        <div
          className='page wrapper'
          style={{
            marginTop: '2em'
          }}
        >
          <Message size='massive' negative>
            <Message.Header>
              We're sorry — something's gone wrong.
            </Message.Header>
            {Raven.lastEventId() && <p>Error ID: {Raven.lastEventId()}</p>}
            <p>
              Our team has been notified, but you can send us more details. We
              appreciate you.
            </p>
            <Button
              onClick={() => Raven.lastEventId() && Raven.showReportDialog()}
              secondary
            >
              Send report
            </Button>
          </Message>
        </div>
      )
    } else {
      return this.props.children
    }
  }
}

export default ErrorBoundary
