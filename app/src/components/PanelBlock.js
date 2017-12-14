import React from 'react'
import PropTypes from 'prop-types'
import './PanelBlock.css'

const propTypes = {
  title: PropTypes.string.isRequired,
  classes: PropTypes.string,
  children: PropTypes.node
}

const PanelBlock = ({title, classes, children}) => (
  <div className={'panel ' + classes}>
    <h4>{title}</h4>
    <hr />
    {children}
  </div>
)

PanelBlock.propTypes = propTypes

PanelBlock.defaultProps = {
  classes: '',
  title: '',
  children: null
}

export default PanelBlock
