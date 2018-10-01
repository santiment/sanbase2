import React from 'react'
import moment from 'moment'
import PropTypes from 'prop-types'
import { Link } from 'react-router-dom'
import './InsightsWidgetItem.css'

const getInsightContonet = htmlContent => {
  let tempHTMLElement = document.createElement('div')
  tempHTMLElement.innerHTML = htmlContent
  const content =
    tempHTMLElement.textContent || tempHTMLElement.querySelector('img')
  tempHTMLElement = null
  return content
}

const createInsightThumbnailImg = htmlImg => (
  <img src={htmlImg.src} alt={htmlImg.alt || 'Insight thumbnail'} />
)

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
  let insightContent = getInsightContonet(text)
  if (typeof insightContent === 'object') {
    insightContent = createInsightThumbnailImg(insightContent)
  }
  return (
    <div className='InsightsWidgetItem'>
      <h2 className='InsightsWidgetItem__title'>
        <Link to={`/insights/${id}`}>{title}</Link>
      </h2>
      <div className='InsightsWidgetItem__content'>{insightContent}</div>
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
