import React, { Fragment } from 'react'
import moment from 'moment'
import PropTypes from 'prop-types'
import { Link } from 'react-router-dom'
import './InsightsWidgetItem.css'

const CHARACTERS_AMOUNT_FIT_IN_ONE_LINE = 36

const getInsightContent = htmlContent => {
  let tempHTMLElement = document.createElement('div')
  tempHTMLElement.innerHTML = htmlContent
  const content =
    tempHTMLElement.textContent.length > CHARACTERS_AMOUNT_FIT_IN_ONE_LINE
      ? tempHTMLElement.textContent
      : {
        text: tempHTMLElement.textContent,
        img: tempHTMLElement.querySelector('img')
      }
  tempHTMLElement = null
  return content
}

const createInsightThumbnail = thumbnail => {
  const content = (
    <Fragment>
      {thumbnail.text}
      {thumbnail.img ? (
        <img
          src={thumbnail.img.src}
          alt={thumbnail.img.alt || 'Insight thumbnail'}
        />
      ) : null}
    </Fragment>
  )
  thumbnail.img = null
  return content
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
  let insightContent = getInsightContent(text)
  if (typeof insightContent === 'object') {
    insightContent = createInsightThumbnail(insightContent)
  }
  return (
    <div className='InsightsWidgetItem'>
      <h2 className='InsightsWidgetItem__title'>
        <Link to={`/insights/${id}`}>{title}</Link>
      </h2>
      <div className='InsightsWidgetItem__article-content'>
        <div className='InsightsWidgetItem__text'>{insightContent}</div>
      </div>
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
