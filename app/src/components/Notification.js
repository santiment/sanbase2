import React, { Component } from 'react'
import { connect } from 'react-redux'
import { NotificationStack } from 'react-notification'

class Notification extends Component {
  state = { // eslint-disable-line
    notifications: []
  }

  componentWillReceiveProps (newProps) {
    if (newProps.notification !== null) {
      this.setState({
        notifications: [...this.state.notifications, newProps.notification]
      })
    } else {
      this.setState({
        notifications: []
      })
    }
  }

  render () {
    return (
      <NotificationStack
        notifications={this.state.notifications}
        onDismiss={notification => this.setState({
          notifications: this.state.notifications
            .filter(item => item.key !== notification.key)
        })}
      />
    )
  }
}

const mapStateToProps = state => {
  return {
    notification: state.notification
  }
}

export default connect(mapStateToProps)(Notification)
