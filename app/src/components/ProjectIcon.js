import React from 'react'
import PropTypes from 'prop-types'
import { setDisplayName } from 'recompose'
import './ProjectIcon.css'

export const DefaultIcon = () => ''

export const ProjectIcon = ({ name, size, ticker }) => {
  if (!name) {
    return <DefaultIcon size={size} />
  }
  let imgSource = ''
  try {
    imgSource = require(`../assets/project-icons/${name
      .toString()
      .toLowerCase()
      .split(/[ /.]+/)
      .join('-')}.png`)
  } catch (e) {
    try {
      imgSource = require(`../assets/32x32/${ticker}-32.png`)
    } catch (e) {
      return <DefaultIcon size={size} />
    }
  }
  return <img width={size} alt={name} height={size} src={imgSource} />
}

ProjectIcon.propTypes = {
  size: PropTypes.number,
  name: PropTypes.string.isRequired,
  ticker: PropTypes.string
}

ProjectIcon.defaultProps = {
  size: 16,
  ticker: ''
}

export default setDisplayName('ProjectIcon')(ProjectIcon)
