import React, { Component } from 'react'
import Slider from 'react-slick'
import Widget from '../Widget/Widget'
import InsightsWidgetItem from './InsightsWidgetItem'
import './InsightsWidget.css'
import './SliderWidget.css'
import { graphql } from 'react-apollo'
import { insightsWidgetGQL } from './insightsWidgetGQL'

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

const parseInsightsWidgetGQLProps = ({ data: { allInsights = [] } }) => ({
  insights: allInsights.slice(0, 5)
})

export class InsightsWidget extends Component {
  render () {
    const { insights = [] } = this.props

    return (
      <Widget className='InsightsWidget'>
        <Slider {...sliderSettings}>
          {insights.map(({ id, createdAt, title, user, text, images }) => (
            <InsightsWidgetItem
              key={id}
              id={id}
              title={title}
              user={user}
              images={images}
              text={text}
              createdAt={createdAt}
            />
          ))}
        </Slider>
      </Widget>
    )
  }
}

export default graphql(insightsWidgetGQL, {
  props: parseInsightsWidgetGQLProps
})(InsightsWidget)
