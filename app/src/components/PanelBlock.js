import React from 'react'
import './PanelBlock.css'

const PanelBlock = ({title, classes, content}) => (
  <div className={'panel ' + classes}>
    <h4>{title}</h4>
    <hr />
    {content}
  </div>
)

PanelBlock.defaultProps = {
  classes: '',
  title: '',
  content: ''
}

export default PanelBlock
