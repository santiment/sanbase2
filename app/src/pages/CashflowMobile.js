import React from 'react'
import ProjectsMobile from './Projects/ProjectsMobile'
import withProjectsData from './Projects/withProjectsData'

const CashflowMobile = props => <ProjectsMobile type={'erc20'} {...props} />

export default withProjectsData({type: 'erc20'})(CashflowMobile)
