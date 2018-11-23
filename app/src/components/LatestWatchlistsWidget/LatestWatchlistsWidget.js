import React from 'react'
import { graphql } from 'react-apollo'
import Slider from 'react-slick'
import Widget from '../Widget/Widget'
import LatestWatchlistsWidgetItem from './LatestWatchlistsWidgetItem'
import { latsetWatchlistsGQL } from './latsetWatchlistsGQL'
import { sliderSettings } from '../InsightsWidget/InsightsWidget'
import styles from './LatestWatchlists.module.css'

const LatestWatchlistsWidget = ({ data: { fetchAllPublicUserLists = [] } }) => {
  return (
    <Widget className={styles.widget} title={'Latest public Watchlists'}>
      <Slider {...sliderSettings}>
        {fetchAllPublicUserLists.map(
          ({ id, name, listItems, isertedAt, user }) => (
            <LatestWatchlistsWidgetItem
              key={id}
              id={id}
              name={name}
              listItems={listItems || []}
              createdAt={isertedAt}
              user={user || {}}
            />
          )
        )}
      </Slider>
    </Widget>
  )
}

export default graphql(latsetWatchlistsGQL)(LatestWatchlistsWidget)
