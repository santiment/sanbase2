import React from 'react';
import { redirect_to } from '../../lib/nextjs_utils';

export default class extends React.Component {
  static async getInitialProps({ res }) {
    return redirect_to(res, "/cashflow");
  }
}
