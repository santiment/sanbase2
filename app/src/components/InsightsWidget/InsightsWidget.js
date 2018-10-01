import React from 'react'
import PropTypes from 'prop-types'
import Slider from 'react-slick'
import { graphql } from 'react-apollo'
import Widget from '../Widget/Widget'
import InsightsWidgetItem from './InsightsWidgetItem'
import { insightsWidgetGQL } from './insightsWidgetGQL'
import './InsightsWidget.css'
import './SliderWidget.css'

const sliderSettings = {
  dots: true,
  infinite: true,
  speed: 500,
  slidesToShow: 1,
  slidesToScroll: 1,
  autoplaySpeed: 70000,
  autoplay: true,
  arrows: false
}

const parseInsightsWidgetGQLProps = ({ data: { allInsights = [] } }) => ({
  insights: allInsights.slice(0, 5)
})

const propTypes = {
  insights: PropTypes.arrayOf(
    PropTypes.shape({
      id: PropTypes.string.isRequired,
      createdAt: PropTypes.string.isRequired,
      title: PropTypes.string.isRequired,
      text: PropTypes.string.isRequired,
      user: PropTypes.shape({
        username: PropTypes.string.isRequired,
        id: PropTypes.string.isRequired
      })
    })
  ).isRequired
}

const InsightsWidget = ({ insights }) => {
  return (
    <Widget className='InsightsWidget'>
      <Slider {...sliderSettings}>
        {insights.map(({ id, createdAt, title, user, text }) => (
          <InsightsWidgetItem
            key={id}
            id={id}
            title={title}
            user={user}
            text={text}
            createdAt={createdAt}
          />
        ))}
      </Slider>
    </Widget>
  )
}

InsightsWidget.propTypes = propTypes
InsightsWidget.defaultProps = {
  insights: []
}

export default graphql(insightsWidgetGQL, {
  props: parseInsightsWidgetGQLProps
})(InsightsWidget)
