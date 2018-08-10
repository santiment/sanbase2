import React from 'react'
import PropTypes from 'prop-types'
import { Input } from 'semantic-ui-react'
import './CreateWatchlistBtn.css'

const initialState = {
  newTitle: ''
}

class CreateWatchlistBtn extends React.Component {
  state = initialState

  componentDidUpdate (prevProps) {
    if (
      this.props.watchlistUi.newItemSuccess !==
      prevProps.watchlistUi.newItemSuccess
    ) {
      this.setState({ newTitle: initialState.newTitle })
    }
  }

  handleOnChange = (e, data) => {
    this.setState({ newTitle: data.value })
  }

  handleCreateWatchlist = () => {
    const name = this.state.newTitle
    if (name && name.length > 0) {
      this.props.createWatchlist({
        name: this.state.newTitle.toLowerCase()
      })
    }
  }

  render () {
    return (
      <div className='create-new-watchlist-btn'>
        <Input
          disabled={this.props.watchlistUi.newItemPending}
          value={this.state.newTitle}
          action={{
            color: 'google plus',
            labelPosition: 'left',
            icon: 'plus',
            content: 'create',
            onClick: this.handleCreateWatchlist
          }}
          onChange={this.handleOnChange}
          onKeyPress={(e, data) => {
            if (e.key === 'Enter') {
              this.handleCreateWatchlist()
            }
          }}
          actionPosition='left'
        />
      </div>
    )
  }
}

CreateWatchlistBtn.propTypes = {
  createWatchlist: PropTypes.func.isRequired
}

export default CreateWatchlistBtn
