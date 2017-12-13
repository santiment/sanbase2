import React from 'react'
import './PanelBlock.css'

const PanelBlock = ({title, classes, children}) => (
  <div className={'panel ' + classes}>
    <h4>{title}</h4>
    <hr />
    {children}
  </div>
)

PanelBlock.defaultProps = {
  classes: '',
  title: '',
  children: ''
}

export default PanelBlock
