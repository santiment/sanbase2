import React from 'react'
import moment from 'moment'
import { Tooltip } from 'recharts'
import { formatterCurrency } from './../../utils/formatting'

const TooltipFormatter = date => moment(date).format('dddd, MMM DD YYYY')

const tooltip = () => (
  <Tooltip labelFormatter={TooltipFormatter} formatter={formatterCurrency} />
)

export default tooltip
