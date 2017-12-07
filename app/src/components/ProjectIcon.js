import React from 'react'
import PropTypes from 'prop-types'

const ProjectIcon = ({name, size}) => {
  if (!name) {
    return (
      <span className='project-icon-default' />
    )
  }
  let imgSource = ''
  try {
    imgSource = require(`../assets/project-icons/${name.toString().toLowerCase().split(' ').join('-')}.png`)
  } catch (e) {
    // pass
  }
  return (
    <img
      width={size}
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
