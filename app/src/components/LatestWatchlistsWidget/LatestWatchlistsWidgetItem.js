import React from 'react'
import moment from 'moment'
import { Link } from 'react-router-dom'
import styles from './LatestWatchlists.module.css'

const MAX_LIST_ITEMS = 2

const InsightsWidgetItem = ({
  id,
  name,
  createdAt,
  listItems,
  user: { username, id: userId }
}) => {
  const remainingItemsCount = listItems.length - MAX_LIST_ITEMS
  const isLongList = remainingItemsCount > 0

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
