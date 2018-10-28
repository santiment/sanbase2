import React, { Fragment } from 'react'
import moment from 'moment'
import PropTypes from 'prop-types'
import { Link } from 'react-router-dom'
// import './InsightsWidgetItem.css'

// const CHARACTERS_AMOUNT_FIT_IN_ONE_LINE = 36

// const getInsightContent = htmlContent => {
//   let tempHTMLElement = document.createElement('div')
//   tempHTMLElement.innerHTML = htmlContent
//   const content =
//     tempHTMLElement.textContent.length > CHARACTERS_AMOUNT_FIT_IN_ONE_LINE
//       ? tempHTMLElement.textContent
//       : {
//         text: tempHTMLElement.textContent,
//         img: tempHTMLElement.querySelector('img')
//       }
//   tempHTMLElement = null
//   return content
// }

// const propTypes = {
//   id: PropTypes.string.isRequired,
//   createdAt: PropTypes.string.isRequired,
//   title: PropTypes.string.isRequired,
//   text: PropTypes.string.isRequired,
//   user: PropTypes.shape({
//     username: PropTypes.string.isRequired,
//     id: PropTypes.string.isRequired
//   })
// }

const InsightsWidgetItem = ({
  id,
  name,
  createdAt,
  listItems,
  user: { username, id: userId }
}) => {
  // let insightContent = getInsightContent(text)
  // if (typeof insightContent === 'object') {
  //   insightContent = createInsightThumbnail(insightContent)
  // }
  return (
    <div className='InsightsWidgetItem'>
      <h3 className='InsightsWidgetItem__title'>
        <Link to={`/assets/list?name=${name}@${id}`}>{name}</Link>
      </h3>
      <div className='InsightsWidgetItem__content'>
        This watchlist contains {listItems.length} items.
        <Link to={`/assets/list?name=${name}@${id}`}>And others...</Link>
      </div>
      <div className='InsightsWidgetItem__bottom'>
        <h4 className='InsightsWidgetItem__info InsightsWidgetItem__info_author'>
          by {username}
        </h4>
        <h4 className='InsightsWidgetItem__info InsightsWidgetItem__info_time'>
          {moment(createdAt).format('MMM DD, YYYY')}
        </h4>
      </div>
    </div>
  )
}

// InsightsWidgetItem.propTypes = propTypes

export default InsightsWidgetItem
