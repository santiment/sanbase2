import React from 'react'
import moment from 'moment'
import { Link } from 'react-router-dom'
import { Icon } from 'semantic-ui-react'
import './InsightsWidgetItem.css'

const getTagsStrippedText = text => {
  let tempHTMLElement = document.createElement('p')
  tempHTMLElement.innerHTML = text
  const insightText = tempHTMLElement.textContent
  tempHTMLElement = null
  return insightText
}

const InsightsWidgetItem = ({
  id,
  createdAt,
  title,
  text,
  user: { username, id: userId },
  images
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

export default InsightsWidgetItem
