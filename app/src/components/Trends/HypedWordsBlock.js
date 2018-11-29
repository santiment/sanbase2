import React from 'react'
import cx from 'classnames'
import HypedWord from './HypedWord'
import styles from './HypedWords.module.css'

const HypedWords = ({ trends, compiled, latest }) => (
  <div className={styles.HypedWords}>
    <h4>Compiled {compiled} UTC</h4>
    <div className={cx(styles.HypedWordsBlock, { [styles.latest]: latest })}>
      {trends &&
        trends.map((trend, index) => (
          <HypedWord key={index} {...trend} latest={latest} />
        ))}
    </div>
  </div>
)

export default HypedWords
