import React from 'react'
import { Helmet } from 'react-helmet'
import { connect } from 'react-redux'
import ManagerPrivacyActivity from './../components/ManagerPrivacyActivity'
import { checkIsLoggedIn } from './UserSelectors'

const PrivacyPolicyPage = ({isLoggedIn}) => (
  <div className='page'>
    <Helmet>
      <title>Privacy Policy</title>
    </Helmet>

    <div className='page-head'>
      <h2>Privacy Statement</h2>
      <p>Last updated May 2018</p>
    </div>

    <br />

    <div className='panel'>
      <p>
        This Policy explains when and why we collect personal information in relation to you, how we use it, the conditions in which we may disclose it to others and how we keep it secure.
      </p>

      <h2>Who are We?</h2>
      <p>
        We are Santiment BG EOOD, UIC 204961660, having our seat and registered address at floor 5, office 4, Puzzle Coworking Space Building, 47 Cherni Vrah Blvd., Sofia, Bulgaria (“We”, “Us”, “Our”). We are the data controller of your personal data provided by you on Our website.
      </p>

      <h2>What personal data do we collect on you?</h2>
      <p>
        We only collect your personal data needed for your registration and creation of a user account on Our website. This includes your name, email address and information on your transactions through your account.
      </p>

      <h2>Why do we process your personal data?</h2>
      <p>
        We process personal information for specific purposes. We process your personal data provided by you during your registration on Our website to support your user account and provide you the full range of services available on Our website regarding the trading with crypto currencies.
      </p>

      <h2>Who else has access to your personal data?</h2>
      <p>
        We may disclose your personal information provided by you during your registration on Our website to other third parties. These third parties include:
        Other companies from Our corporate group, including Our mother company in Switzerland. Any transfers within Our corporate group will be made solely on the grounds of concluded within the group data processing agreements;
        Our suppliers of IT services which deliver, develop, and/or maintain the IT systems used by Us;
        Our professional advisers such as Our auditors and lawyers;
        Relevant state authorities to which We have to disclose your personal data to the extent required so by the law applicable to Us;
        Any other party to whom you authorise Us to disclose your personal data to.
      </p>

      <p>
        In any event, when disclosing your personal data, We will take reasonable steps to protect your personal information against unauthorised disclosure and will always disclose your personal data based on a valid legal ground to third parties on a need-to-know basis.
      </p>

      <p>
        We do not transfer your personal data outside of the European Economic Area. If such transfers appear to be necessary for the provision of Our services, We will always put in place adequate safeguards for them.
      </p>

      <h2>What are your rights concerning your personal data?</h2>
      <p>
        You have the following rights with respect to the personal data that We process for you:
        the right to request a copy of your personal data which We hold about you;
        the right to request that We correct any personal data if it is found to be inaccurate or out of date;
        the right to request your personal data to be erased where it is no longer necessary for Us to retain such data;
        if processing is based on consent, contract or automated decision mechanisms, the right to request from Us to provide you with the personal data directly obtained from you and, where possible, to transmit such data directly to another data controller (known as the right to data portability),
        the right to withdraw your consent to the processing at any time,
        the right, where there is a dispute in relation to the accuracy or processing of your personal data, to request a restriction on further processing;
        the right to lodge a complaint with the supervisory authority. As a company established under the laws of the Republic of Bulgaria, the competent supervisory authority regarding Our compliance with the data protection laws is the Bulgarian Commission on Personal Data Protection (www.cpdp.bg).
      </p>

      <p>
        Your rights might be subject to certain restrictions imposed by the data protection laws. If your request to exercise any of your rights places Us or any of Our related companies in a breach of the applicable data protection laws or codes of conduct, We may refuse to fulfil your request.
      </p>

      <h2>How long will We retain your personal data?</h2>
      <p>
        We will retain your personal information while you have an active account on Our website. If you decide to deregister by sending as an email to admin@santiment.net, We will without any undue delay delete in a manner that does not allow for recovery of your personal data. If you deregister from Our website, We will no longer be in the position to provide Our services to you.
      </p>

      <p>
        You can contact Us at any time to withdraw your consent to receive Our marketing materials. If you withdraw your consent, We will immediately seize to send you marketing materials but We will continue to process your personal data necessary for your user account on Our website.
      </p>

      <h2>How do We protect your personal data?</h2>
      <p>
        We will take reasonable efforts to protect your personal information in Our possession or Our control by making reasonable security arrangements to prevent unauthorised access, collection, use, disclosure, copying, modification, disposal or similar risks.
      </p>

      <p>
        While we strive to protect your personal information, we cannot nor retain liability or ensure the security of the information you transmit to Us via the Internet and we urge you to take every precaution to protect your personal data when you use such platforms. We recommend that you change your passwords often, use a combination of letters and numbers, and ensure that you use a secure browser.
      </p>

      <h2>Will We change the way We handle your personal data?</h2>
      <p>
        We may amend this Policy at any time to reflect any changes We may make in the manner We handle your personal data. We will always reflect in this Policy the date of it latest revision. If We have made any material changes to this Policy, We will always underline them in the way We provide you with information and will, when possible, inform you directly on the amendments.
      </p>

      <h2>How can you contact Us?</h2>
      <p>
        If you have any questions in respect of the manner in which we process your personal data, let Us know by sending Us an email to admin@santiment.net or by post at floor 5, office 4, Puzzle Coworking Space Building, 47 Cherni Vrah Blvd., Sofia, Bulgaria.
      </p>
    </div>
    <br />
    {isLoggedIn && <ManagerPrivacyActivity />}
  </div>
)

const mapStateToProps = state => {
  return {
    isLoggedIn: checkIsLoggedIn(state)
  }
}

export default connect(mapStateToProps)(PrivacyPolicyPage)
