import React from 'react'
import PropTypes from 'prop-types'
import { Message } from 'semantic-ui-react'

const propTypes = {
  title: PropTypes.string.isRequired,
  classes: PropTypes.string,
  children: PropTypes.node,
  isUnauthorized: PropTypes.bool
}

const PanelBlock = ({
  title = '',
  classes = '',
  children,
  isUnauthorized = false,
  isLoading = true
}) => (
  <div className={'panel ' + classes}>
    <h4>{title}</h4>
    <hr />
    {isLoading ? 'Loading...'
      : isUnauthorized
        ? <Message
          warning
          header='You must login before you can view that!'
          content='Visit our login page, then try again.'
        />
        : children}
  </div>
)

PanelBlock.propTypes = propTypes

export default PanelBlock
