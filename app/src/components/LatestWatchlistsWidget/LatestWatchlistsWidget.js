import React from 'react'
import Widget from '../Widget/Widget'
import LatestWatchlistsWidgetItem from './LatestWatchlistsWidgetItem'
import { graphql } from 'react-apollo'
import { latsetWatchlistsGQL } from './latsetWatchlistsGQL'
import Slider from 'react-slick'

const sliderSettings = {
  dots: true,
  infinite: true,
  speed: 500,
  slidesToShow: 1,
  slidesToScroll: 1,
  autoplaySpeed: 7000,
  autoplay: true,
  arrows: false
}

const LatestWatchlistsWidget = ({ data: { fetchAllPublicUserLists = [] } }) => {
  return (
    <Widget title={'Latest public Watchlists'}>
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
