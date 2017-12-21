import React from 'react'
import PropTypes from 'prop-types'
import './ProjectIcon.css'

export const DefaultIcon = ({size}) => (
  <span
    width={size}
    className='project-icon-default' />
)

export const ProjectIcon = ({name, size}) => {
  if (!name) {
    return (
      <DefaultIcon size={size} />
    )
  }
  let imgSource = ''
  try {
    imgSource = require(`../assets/project-icons/${name.toString().toLowerCase().split((/[ /.]+/)).join('-')}.png`)
  } catch (e) {
    return (
      <DefaultIcon size={size} />
    )
  }
  return (
    <img
      width={size}
      alt={name}
      height={size}
      src={imgSource} />
  )
}

ProjectIcon.propTypes = {
  size: PropTypes.number,
  name: PropTypes.string.isRequired
}

ProjectIcon.defaultProps = {
  size: 16
}

export default ProjectIcon
