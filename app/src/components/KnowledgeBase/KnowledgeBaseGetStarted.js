import React from 'react'
import KnowledgeBaseSection from './KnowledgeBaseSection'
import KnowledgeBaseGetStartedParts from './KnowledgeBaseGetStarted/KnowledgeBaseGetStartedParts'
import KnowledgeBaseGetStartedMetrics from './KnowledgeBaseGetStarted/KnowledgeBaseGetStartedMetrics'
import KnowledgeBaseGetStartedExplore from './KnowledgeBaseGetStarted/KnowledgeBaseGetStartedExplore'
import KnowledgeBaseGetStartedLogin from './KnowledgeBaseGetStarted/KnowledgeBaseGetStartedLogin'
import styles from './KnowledgeBaseGetStarted.module.scss'

const KnowledgeBaseGetStarted = ({ id }) => {
  return (
    <KnowledgeBaseSection
      id={id}
      title='Getting Started with SANbase'
      lastUpdated='11-17-18'
    >
      <div className={styles.content}>
        Quick jump to a section below:
        <ol>
          <li>
            <a href='#parts'>Parts of SANbase</a>
          </li>
          <li>
            <a href='#metrics'>Metrics We Offer</a>
          </li>
          <li>
            <a href='#explore'>Explore for Free</a>
          </li>
          <li>
            <a href='#logging'>Logging In</a>
          </li>
          <li>
            <a href='#staking'>Staking</a>
          </li>
        </ol>
        <hr />
        <KnowledgeBaseGetStartedParts />
        <hr />
        <KnowledgeBaseGetStartedMetrics />
        <hr />
        <KnowledgeBaseGetStartedExplore />
        <hr />
        <KnowledgeBaseGetStartedLogin />
      </div>
    </KnowledgeBaseSection>
  )
}

export default KnowledgeBaseGetStarted
