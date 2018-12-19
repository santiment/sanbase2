import React from 'react'
import cx from 'classnames'
import moment from 'moment'
import HypedWord from './HypedWord'
import styles from './HypedWords.module.scss'

const compare = (a, b) => a.score - b.score

const HypedWords = ({ trends, compiled, latest }) => (
  <div className={styles.HypedWords}>
    <h4>Compiled {moment(compiled).format('YYYY-MM-DD HH:mm')}</h4>
    <div className={cx(styles.HypedWordsBlock, { [styles.latest]: latest })}>
      {trends &&
        trends
          .sort(compare)
          .reverse()
          .map((trend, index) => (
            <HypedWord key={index} {...trend} latest={latest} />
          ))}
    </div>
  </div>
)

export default HypedWords
