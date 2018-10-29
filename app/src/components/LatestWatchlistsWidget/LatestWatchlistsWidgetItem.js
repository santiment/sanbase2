import React, { Fragment } from 'react'
import moment from 'moment'
import PropTypes from 'prop-types'
import { Link } from 'react-router-dom'
import styles from './LatestWatchlists.module.css'

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

const MAX_LIST_ITEMS = 2

const InsightsWidgetItem = ({
  id,
  name,
  createdAt,
  listItems,
  user: { username, id: userId }
}) => {
  const remainingItemsCount = listItems.length - MAX_LIST_ITEMS
  console.log('TCL: remainingItemsCount', remainingItemsCount)
  const isLongList = remainingItemsCount > 0
  console.log('TCL: isLongList', isLongList)

  return (
    <div className={styles.wrapper}>
      <h3 className={styles.title}>
        <Link to={`/assets/list?name=${name}@${id}`}>{name}</Link>
      </h3>
      <div className={styles.content}>
        This watchlist includes:
        <ul className={styles.list}>
          {listItems.slice(0, MAX_LIST_ITEMS).map(({ project: { name } }) => (
            <li>{name}</li>
          ))}
          {isLongList && <li>And {remainingItemsCount} more projects...</li>}
        </ul>
      </div>
      <div className={styles.bottom}>
        <h4 className={styles.info + ' ' + styles.info_author}>
          by {username}
        </h4>
        <h4 className={styles.info + ' ' + styles.info_time}>
          {moment(createdAt).format('MMM DD, YYYY')}
        </h4>
      </div>
    </div>
  )
}

export default InsightsWidgetItem
