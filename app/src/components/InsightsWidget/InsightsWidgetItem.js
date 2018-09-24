import React from 'react'
import moment from 'moment'
import PropTypes from 'prop-types'
import { Link } from 'react-router-dom'
import './InsightsWidgetItem.css'

const getTagsStrippedText = text => {
  let tempHTMLElement = document.createElement('p')
  tempHTMLElement.innerHTML = text
  const insightText = tempHTMLElement.textContent
  tempHTMLElement = null
  return insightText
}

const propTypes = {
  id: PropTypes.string.isRequired,
  createdAt: PropTypes.string.isRequired,
  title: PropTypes.string.isRequired,
  text: PropTypes.string.isRequired,
  user: PropTypes.shape({
    username: PropTypes.string.isRequired,
    id: PropTypes.string.isRequired
  })
}

const InsightsWidgetItem = ({
  id,
  createdAt,
  title,
  text,
  user: { username, id: userId }
}) => {
  const insightText = getTagsStrippedText(text)
  return (
    <div className='InsightsWidgetItem'>
      <h2 className='InsightsWidgetItem__title'>
        <Link to={`/insights/${id}`}>{title}</Link>
      </h2>
      <p className='InsightsWidgetItem__text'>{insightText}</p>
      <div className='InsightsWidgetItem__bottom'>
        <h4 className='InsightsWidgetItem__info InsightsWidgetItem__info_author'>
          by <Link to={`/insights/users/${userId}`}>{username}</Link>
        </h4>
        <h4 className='InsightsWidgetItem__info InsightsWidgetItem__info_time'>
          {moment(createdAt).format('MMM DD, YYYY')}
        </h4>
      </div>
    </div>
  )
}

InsightsWidgetItem.propTypes = propTypes

export default InsightsWidgetItem
