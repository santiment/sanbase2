import Head from 'next/head'

export default (props) => (
  <Head>
    <meta charSet='utf-8' />
    <title>SANBase</title>
    <meta name='viewport' content='initial-scale=1.0, width=device-width, shrink-to-fit=no' />
    <link rel='shortcut icon' href='/static/cashflow/img/favicon.png' />
    <link rel='stylesheet' href='//cdnjs.cloudflare.com/ajax/libs/semantic-ui/2.2.12/semantic.min.css' />
    {process.env.NODE_ENV === 'production' &&
    <script dangerouslySetInnerHTML={{ __html: `
      (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
              (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
          m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
      })(window,document,'script','https://www.google-analytics.com/analytics.js','ga');

      ga('create', 'UA-100571693-1', 'auto');
      ga('send', 'pageview');
    `}} />}
    { props.children }
  </Head>
)
